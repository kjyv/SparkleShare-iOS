//
//  ShareViewController.m
//  ShareExtension
//

#import "ShareViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const kAppGroupID = @"group.com.sb.SparkleShare";

@interface ShareViewController ()

@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;

@end

@implementation ShareViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.text = @"Preparing...";
    [self.view addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:16],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];

    [self.spinner startAnimating];
    [self processInputItems];
}

- (void)processInputItems {
    NSExtensionItem *item = self.extensionContext.inputItems.firstObject;
    NSItemProvider *provider = item.attachments.firstObject;

    if (!provider) {
        [self showErrorAndCancel:@"No file was provided."];
        return;
    }

    // Try loading as file URL first (UTType file URL), then fall back to generic item
    if ([provider hasItemConformingToTypeIdentifier:UTTypeFileURL.identifier]) {
        [provider loadItemForTypeIdentifier:UTTypeFileURL.identifier options:nil completionHandler:^(NSURL *url, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error || !url) {
                    [self showErrorAndCancel:@"Could not read the file."];
                    return;
                }
                [self handleFileURL:url];
            });
        }];
    } else if ([provider hasItemConformingToTypeIdentifier:UTTypeItem.identifier]) {
        [provider loadItemForTypeIdentifier:UTTypeItem.identifier options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    [self showErrorAndCancel:@"Could not read the file."];
                    return;
                }
                id obj = item;
                if ([obj isKindOfClass:[NSURL class]]) {
                    [self handleFileURL:(NSURL *)obj];
                } else if ([obj isKindOfClass:[NSData class]]) {
                    // Data without a URL — we need a filename from the extension item
                    NSString *filename = [self suggestedFilenameFromItem:self.extensionContext.inputItems.firstObject] ?: @"SharedFile";
                    [self handleFileData:(NSData *)obj filename:filename];
                } else {
                    [self showErrorAndCancel:@"Unsupported file type."];
                }
            });
        }];
    } else {
        [self showErrorAndCancel:@"Unsupported file type."];
    }
}

- (NSString *)suggestedFilenameFromItem:(NSExtensionItem *)item {
    if (item.attributedContentText) {
        return item.attributedContentText.string;
    }
    return nil;
}

- (void)handleFileURL:(NSURL *)url {
    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (accessed) [url stopAccessingSecurityScopedResource];

    if (!data) {
        [self showErrorAndCancel:@"Could not read the file data."];
        return;
    }

    NSString *filename = url.lastPathComponent;
    [self handleFileData:data filename:filename];
}

- (void)handleFileData:(NSData *)data filename:(NSString *)filename {
    NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAppGroupID];
    NSDictionary *sharedFiles = [sharedDefaults dictionaryForKey:@"SSSharedFiles"];
    NSDictionary *fileInfo = sharedFiles[filename];

    if (!fileInfo) {
        NSString *msg = [NSString stringWithFormat:@"\"%@\" was not previously opened in SparkleShare. Open the file in SparkleShare first, then try sharing again.", filename];
        [self showErrorAndCancel:msg];
        return;
    }

    NSString *linkString = [sharedDefaults stringForKey:@"linkString"];
    NSString *identCode = [sharedDefaults stringForKey:@"identCode"];
    NSString *authCode = [sharedDefaults stringForKey:@"authCode"];

    if (!linkString || !identCode || !authCode) {
        [self showErrorAndCancel:@"SparkleShare is not linked to a server. Open SparkleShare and link your device first."];
        return;
    }

    NSString *fileAPIURL = fileInfo[@"fileAPIURL"];
    NSString *projectFolderSSID = fileInfo[@"projectFolderSSID"];
    NSString *path = [NSString stringWithFormat:@"/api/putFile/%@?%@", projectFolderSSID, fileAPIURL];

    // Build the upload URL
    NSString *baseString = linkString;
    while ([baseString hasSuffix:@"/"]) {
        baseString = [baseString substringToIndex:baseString.length - 1];
    }
    while ([path hasPrefix:@"/"]) {
        path = [path substringFromIndex:1];
    }
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", baseString, path];
    NSURL *requestURL = [NSURL URLWithString:urlString];

    if (!requestURL) {
        [self showErrorAndCancel:@"Invalid server URL."];
        return;
    }

    self.statusLabel.text = @"Uploading...";

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:identCode forHTTPHeaderField:@"X-SPARKLE-IDENT"];
    [request setValue:authCode forHTTPHeaderField:@"X-SPARKLE-AUTH"];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    [request setTimeoutInterval:120];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];

    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromData:data completionHandler:^(NSData *responseData, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self showErrorAndCancel:[NSString stringWithFormat:@"Upload failed: %@", error.localizedDescription]];
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                [sharedDefaults setBool:YES forKey:@"SSNeedsRefresh"];
                [self showSuccessAndComplete];
            } else {
                [self showErrorAndCancel:[NSString stringWithFormat:@"Server returned error %ld.", (long)httpResponse.statusCode]];
            }
        });
    }];

    [task resume];
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAppGroupID];
        BOOL allowSelfSigned = [sharedDefaults boolForKey:@"allowSelfSignedCertificates"];

        if (allowSelfSigned && challenge.protectionSpace.serverTrust) {
            NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
            return;
        }
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

#pragma mark - UI Helpers

- (void)showSuccessAndComplete {
    [self.spinner stopAnimating];
    self.statusLabel.text = @"Uploaded!";

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    });
}

- (void)showErrorAndCancel:(NSString *)message {
    [self.spinner stopAnimating];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SparkleShare"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSError *error = [NSError errorWithDomain:@"com.sb.SparkleShare.ShareExtension" code:0 userInfo:@{NSLocalizedDescriptionKey: message}];
        [self.extensionContext cancelRequestWithError:error];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end

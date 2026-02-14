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

@property (nonatomic, strong) NSData *fileData;
@property (nonatomic, copy) NSString *fileName;

@property (nonatomic, strong) NSDictionary *folderContext;
@property (nonatomic, strong) NSArray *folderFiles;

@property (nonatomic, strong) UINavigationBar *navBar;
@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, copy) NSString *adjustedFileName;

@property (nonatomic, copy) NSString *linkString;
@property (nonatomic, copy) NSString *identCode;
@property (nonatomic, copy) NSString *authCode;

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
                    // Data without a URL -- we need a filename from the extension item
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
    self.fileData = data;
    self.fileName = filename;

    NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAppGroupID];

    self.linkString = [sharedDefaults stringForKey:@"linkString"];
    self.identCode = [sharedDefaults stringForKey:@"identCode"];
    self.authCode = [sharedDefaults stringForKey:@"authCode"];

    if (!self.linkString || !self.identCode || !self.authCode) {
        [self showErrorAndCancel:@"SparkleShare is not linked to a server. Open SparkleShare and link your device first."];
        return;
    }

    // Read folder context from App Group defaults
    [sharedDefaults synchronize];
    self.folderContext = [sharedDefaults dictionaryForKey:@"SSCurrentFolder"];

    if (self.folderContext) {
        [self fetchFolderContents];
    } else {
        [self showErrorAndCancel:@"Open a file in SparkleShare first, then share from here."];
    }
}

#pragma mark - Folder Contents

- (void)fetchFolderContents {
    NSString *projectFolderSSID = self.folderContext[@"projectFolderSSID"];
    NSString *folderURL = self.folderContext[@"folderURL"];

    // Strip hash parameter from folderURL
    if (folderURL.length > 0) {
        NSURLComponents *components = [NSURLComponents componentsWithString:
            [NSString stringWithFormat:@"http://localhost/?%@", folderURL]];
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSURLQueryItem *item in components.queryItems) {
            if (![item.name isEqualToString:@"hash"]) {
                [filtered addObject:item];
            }
        }
        components.queryItems = filtered;
        folderURL = components.percentEncodedQuery ?: @"";
    }

    NSString *path;
    if (folderURL.length > 0) {
        path = [NSString stringWithFormat:@"/api/getFolderContent/%@?%@", projectFolderSSID, folderURL];
    } else {
        path = [NSString stringWithFormat:@"/api/getFolderContent/%@", projectFolderSSID];
    }

    NSURL *requestURL = [self buildURLWithPath:path];
    if (!requestURL) {
        [self showErrorAndCancel:@"Invalid server URL."];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    [request setHTTPMethod:@"GET"];
    [request setValue:self.identCode forHTTPHeaderField:@"X-SPARKLE-IDENT"];
    [request setValue:self.authCode forHTTPHeaderField:@"X-SPARKLE-AUTH"];
    [request setTimeoutInterval:30];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *responseData, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self showErrorAndCancel:[NSString stringWithFormat:@"Could not load folder: %@", error.localizedDescription]];
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
                [self showErrorAndCancel:[NSString stringWithFormat:@"Server returned error %ld.", (long)httpResponse.statusCode]];
                return;
            }

            NSError *jsonError;
            id json = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&jsonError];
            if (jsonError || ![json isKindOfClass:[NSArray class]]) {
                [self showErrorAndCancel:@"Could not parse folder contents."];
                return;
            }

            // Filter to files only
            NSMutableArray *files = [NSMutableArray array];
            for (NSDictionary *item in (NSArray *)json) {
                if ([item[@"type"] isEqualToString:@"file"]) {
                    [files addObject:item];
                }
            }
            self.folderFiles = files;
            self.adjustedFileName = [self uniqueFilenameForName:self.fileName inFiles:files];
            [self showFilePickerUI];
        });
    }];
    [task resume];
}

#pragma mark - File Picker UI

- (void)showFilePickerUI {
    [self.spinner stopAnimating];
    self.spinner.hidden = YES;
    self.statusLabel.hidden = YES;

    NSString *folderName = self.folderContext[@"folderName"] ?: @"Folder";

    // Navigation bar
    self.navBar = [[UINavigationBar alloc] init];
    self.navBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.navBar];

    UINavigationItem *navItem = [[UINavigationItem alloc] initWithTitle:folderName];
    navItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                              target:self
                                                                              action:@selector(cancelPressed)];
    [self.navBar setItems:@[navItem]];

    // Table view
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.navBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.navBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.navBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.navBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.folderFiles.count == 0) return 1;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    return self.folderFiles.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return @"Replace existing file";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = @"Save as new file";
        cell.detailTextLabel.text = self.adjustedFileName;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.imageView.image = [UIImage systemImageNamed:@"doc.badge.plus"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSDictionary *fileDict = self.folderFiles[indexPath.row];
    cell.textLabel.text = fileDict[@"name"];
    cell.imageView.image = [UIImage systemImageNamed:@"doc"];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        [self uploadAsNewFile];
        return;
    }

    NSDictionary *fileDict = self.folderFiles[indexPath.row];
    NSString *name = fileDict[@"name"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Replace File"
                                                                  message:[NSString stringWithFormat:@"Replace \"%@\" with the shared file?", name]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self uploadOverwritingFile:fileDict];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Upload

- (void)uploadAsNewFile {
    NSString *projectFolderSSID = self.folderContext[@"projectFolderSSID"];
    NSString *folderPath = self.folderContext[@"folderPath"];

    NSString *newFilePath;
    if (folderPath.length > 0) {
        newFilePath = [NSString stringWithFormat:@"%@/%@", folderPath, self.adjustedFileName];
    } else {
        newFilePath = self.adjustedFileName;
    }

    // Encode for query string values (/ must become %2F)
    NSMutableCharacterSet *valueChars = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [valueChars removeCharactersInString:@"/?&=+"];
    NSString *encodedPath = [newFilePath stringByAddingPercentEncodingWithAllowedCharacters:valueChars];
    NSString *encodedName = [self.adjustedFileName stringByAddingPercentEncodingWithAllowedCharacters:valueChars];

    NSString *path = [NSString stringWithFormat:@"/api/postFile/%@?path=%@&name=%@",
        projectFolderSSID, encodedPath, encodedName];

    NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAppGroupID];
    [sharedDefaults setBool:YES forKey:@"SSUploadedNewFile"];

    [self uploadData:self.fileData toPath:path];
}

- (void)uploadOverwritingFile:(NSDictionary *)fileDict {
    NSString *projectFolderSSID = self.folderContext[@"projectFolderSSID"];
    NSString *fileURL = fileDict[@"url"];

    // Strip hash from file URL
    if (fileURL.length > 0) {
        NSURLComponents *components = [NSURLComponents componentsWithString:
            [NSString stringWithFormat:@"http://localhost/?%@", fileURL]];
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSURLQueryItem *item in components.queryItems) {
            if (![item.name isEqualToString:@"hash"]) {
                [filtered addObject:item];
            }
        }
        components.queryItems = filtered;
        fileURL = components.percentEncodedQuery ?: @"";
    }

    NSString *path = [NSString stringWithFormat:@"/api/putFile/%@?%@", projectFolderSSID, fileURL];
    [self uploadData:self.fileData toPath:path];
}

- (void)uploadData:(NSData *)data toPath:(NSString *)path {
    // Hide table and show spinner
    self.navBar.hidden = YES;
    self.tableView.hidden = YES;
    self.spinner.hidden = NO;
    self.statusLabel.hidden = NO;
    self.statusLabel.text = @"Uploading...";
    [self.spinner startAnimating];

    NSURL *requestURL = [self buildURLWithPath:path];
    if (!requestURL) {
        [self showErrorAndCancel:@"Invalid server URL."];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:self.identCode forHTTPHeaderField:@"X-SPARKLE-IDENT"];
    [request setValue:self.authCode forHTTPHeaderField:@"X-SPARKLE-AUTH"];
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
                NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAppGroupID];
                [sharedDefaults setBool:YES forKey:@"SSNeedsRefresh"];
                [self showSuccessAndComplete];
            } else {
                [self showErrorAndCancel:[NSString stringWithFormat:@"Server returned error %ld.", (long)httpResponse.statusCode]];
            }
        });
    }];
    [task resume];
}

#pragma mark - Helpers

- (NSURL *)buildURLWithPath:(NSString *)path {
    NSString *baseString = self.linkString;
    while ([baseString hasSuffix:@"/"]) {
        baseString = [baseString substringToIndex:baseString.length - 1];
    }
    while ([path hasPrefix:@"/"]) {
        path = [path substringFromIndex:1];
    }
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", baseString, path];
    return [NSURL URLWithString:urlString];
}

- (NSString *)uniqueFilenameForName:(NSString *)name inFiles:(NSArray *)files {
    NSSet *existingNames = [NSSet setWithArray:[files valueForKey:@"name"]];
    if (![existingNames containsObject:name]) return name;

    NSString *baseName = [name stringByDeletingPathExtension];
    NSString *ext = [name pathExtension];
    for (NSInteger i = 2; ; i++) {
        NSString *candidate;
        if (ext.length > 0) {
            candidate = [NSString stringWithFormat:@"%@ %ld.%@", baseName, (long)i, ext];
        } else {
            candidate = [NSString stringWithFormat:@"%@ %ld", baseName, (long)i];
        }
        if (![existingNames containsObject:candidate]) return candidate;
    }
}

- (void)cancelPressed {
    NSError *error = [NSError errorWithDomain:@"com.sb.SparkleShare.ShareExtension" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}];
    [self.extensionContext cancelRequestWithError:error];
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

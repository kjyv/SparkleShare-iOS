//
//  SparkleShareAppDelegate.m
//  SparkleShare
//
//  Created by Sergey Klimov on 07.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "SparkleShareAppDelegate.h"
#import "SelectLoginInputViewController.h"
#import "FolderViewController.h"
#import "FileViewController.h"

#import "StartingViewController.h"
#import "SVProgressHUD.h"
#import "SSConnection.h"

@implementation SparkleShareAppDelegate

@synthesize window = _window;
@synthesize navigationController = _navigationController;
//@synthesize splitViewController = _splitViewController;
@synthesize loginInputViewController = _loginInputViewController;

- (SSConnection *)connection {
    return connection;
}

- (BOOL)application: (UIApplication *) application didFinishLaunchingWithOptions: (NSDictionary *) launchOptions
{
	self.window = [[UIWindow alloc] init];

	self.window.backgroundColor = [UIColor systemBackgroundColor];

	StartingViewController *startingViewController = [[StartingViewController alloc] init];

	self.window.rootViewController = startingViewController;
    [self.window makeKeyAndVisible];

	connection = [[SSConnection alloc] initWithUserDefaults];
    connection.delegate = self;
    [connection establishConnection];

	return YES;
}

- (void)applicationWillResignActive: (UIApplication *) application {
	/*
	   Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
	   Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
	 */
}

- (void)applicationDidEnterBackground: (UIApplication *) application {
	/*
	   Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
	   If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
	 */
}

- (void)applicationWillEnterForeground: (UIApplication *) application {
	/*
	   Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
	 */
}

- (void)applicationDidBecomeActive: (UIApplication *) application {
	NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.sb.SparkleShare"];
	if ([sharedDefaults boolForKey:@"SSNeedsRefresh"]) {
		[sharedDefaults removeObjectForKey:@"SSNeedsRefresh"];

		// Find the FolderViewController directly below the FileViewController
		NSArray *viewControllers = self.navigationController.viewControllers;
		UIViewController *topVC = viewControllers.lastObject;
		if (viewControllers.count >= 2 && [topVC isKindOfClass:[FileViewController class]]) {
			UIViewController *parentVC = viewControllers[viewControllers.count - 2];
			if ([parentVC isKindOfClass:[FolderViewController class]]) {
				FileViewController *fileVC = (FileViewController *)topVC;
				FolderViewController *folderVC = (FolderViewController *)parentVC;
				folderVC.pendingReopenFilename = fileVC.filePreview.filename;
				[folderVC reloadFolder];
			}
		}
	}
}

- (void)applicationWillTerminate: (UIApplication *) application {
	/*
	   Called when the application is about to terminate.
	   Save data if appropriate.
	   See also applicationDidEnterBackground:.
	 */
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    NSData *fileData = [NSData dataWithContentsOfURL:url];
    if (!fileData) return NO;

    NSString *filename = url.lastPathComponent;
    NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.sb.SparkleShare"];
    NSDictionary *sharedFiles = [sharedDefaults dictionaryForKey:@"SSSharedFiles"];
    NSDictionary *fileInfo = sharedFiles[filename];

    if (!fileInfo) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Upload"
            message:@"This file was not previously shared from SparkleShare."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        return NO;
    }

    NSString *alertMessage = [NSString stringWithFormat:@"Overwrite \"%@\" on the server?", filename];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Upload File"
        message:alertMessage
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Overwrite" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *fileAPIURL = fileInfo[@"fileAPIURL"];
        NSString *projectFolderSSID = fileInfo[@"projectFolderSSID"];
        NSString *path = [NSString stringWithFormat:@"/api/putFile/%@?%@", projectFolderSSID, fileAPIURL];

        [SVProgressHUD showWithStatus:@"Uploading..."];
        [self->connection uploadBinaryData:fileData toPath:path success:^{
            [SVProgressHUD dismissWithSuccess:@"Uploaded!"];
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        } failure:^(NSError *error) {
            NSString *errorMsg = [NSString stringWithFormat:@"Upload failed: %@", error.localizedDescription];
            [SVProgressHUD dismissWithError:errorMsg afterDelay:5];
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        }];
    }]];

    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
    return YES;
}

- (void)loginInputViewController: (LoginInputViewController *) loginInputViewController
       willSetLink: (NSURL *) link code: (NSString *) code;
{
    [SVProgressHUD showWithStatus:@"Linking in progress"];
	[connection linkDeviceWithAddress: link code: code];
}


- (void) connectionEstablishingSuccess: (SSConnection *) aConnection {
    //fixme: ugly casting
	id rootFolder = aConnection.rootFolder;
	NSAssert([rootFolder isKindOfClass: [SSFolder class]], @"Return value is not of type SSFolder as expected.");
	FolderViewController *folderViewController = [[FolderViewController alloc] initWithFolder: rootFolder];
	self.navigationController = [[UINavigationController alloc] initWithRootViewController: folderViewController];
	self.window.rootViewController = self.navigationController;
//    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
//        SparkleShareMasterViewController *masterViewController = [[SparkleShareMasterViewController alloc] initWithConnection:aConnection];
//        self.navigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
//        self.window.rootViewController = self.navigationController;
//    } else {
//        SparkleShareMasterViewController *masterViewController = [[SparkleShareMasterViewController alloc] initWithConnection:aConnection];
//        UINavigationController *masterNavigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
//
//        SparkleShareDetailViewController *detailViewController = [[SparkleShareDetailViewController alloc] initWithNibName:@"SparkleShareDetailViewController_iPad" bundle:nil];
//        UINavigationController *detailNavigationController = [[UINavigationController alloc] initWithRootViewController:detailViewController];
//
//        self.splitViewController = [[UISplitViewController alloc] init];
//        self.splitViewController.delegate = detailViewController;
//        self.splitViewController.viewControllers = [NSArray arrayWithObjects:masterNavigationController, detailNavigationController, nil];
//
//        self.window.rootViewController = self.splitViewController;
//    }
}

- (void) connectionEstablishingFailed: (SSConnection *) connection {
    if (!self.loginInputViewController) {
        self.loginInputViewController = [[SelectLoginInputViewController alloc] init];
        self.loginInputViewController.delegate = self;
    }
	
	self.navigationController = [[UINavigationController alloc] initWithRootViewController: self.loginInputViewController];
	self.window.rootViewController = self.navigationController;
}

- (void)connectionLinkingSuccess: (SSConnection *) connection {
    [SVProgressHUD dismissWithSuccess:@"Linked!"];
}

- (void)connectionLinkingFailed: (SSConnection *) connection error: (NSString*) error {
    NSMutableString *errorString = [NSMutableString stringWithString: @"Error during linking: "];
    [errorString appendString:error];
    
    [SVProgressHUD dismissWithError: errorString afterDelay:5];
}

@end

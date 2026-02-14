//
//  FileViewController.m
//  SparkleShare
//
//  Created by Sergey Klimov on 13.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "FileViewController.h"
#import "FilePreview.h"
#import "FolderViewController.h"
#import "UIViewController+AutoPlatformNibName.h"

@implementation FileViewController
@synthesize filePreview = _filePreview;

- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
	[super didReceiveMemoryWarning];

	// Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];
	[self recordSharedFile];
}

- (void)recordSharedFile {
	NSString *filename = self.filePreview.filename;
	NSString *fileAPIURL = self.filePreview.fileAPIURL;
	NSString *projectFolderSSID = self.filePreview.projectFolderSSID;
	if (!filename || !fileAPIURL || !projectFolderSSID) return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *sharedFiles = [[defaults dictionaryForKey:@"SSSharedFiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
	sharedFiles[filename] = @{
		@"fileAPIURL": fileAPIURL,
		@"projectFolderSSID": projectFolderSSID
	};
	[defaults setObject:sharedFiles forKey:@"SSSharedFiles"];
	[defaults synchronize];

	// Also write to the App Group shared suite for the Share Extension
	NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.sb.SparkleShare"];
	[sharedDefaults setObject:sharedFiles forKey:@"SSSharedFiles"];

	// Store folder context for ShareExtension file picker
	// Find parent FolderViewController in nav stack
	FolderViewController *parentFolderVC = nil;
	NSArray *viewControllers = self.navigationController.viewControllers;
	for (NSInteger i = viewControllers.count - 1; i >= 0; i--) {
		if ([viewControllers[i] isKindOfClass:[FolderViewController class]]) {
			parentFolderVC = viewControllers[i];
			break;
		}
	}
	if (parentFolderVC) {
		NSString *folderPath = nil;
		if (parentFolderVC.folder.url) {
			NSURLComponents *components = [NSURLComponents componentsWithString:
				[NSString stringWithFormat:@"http://localhost/?%@", parentFolderVC.folder.url]];
			for (NSURLQueryItem *item in components.queryItems) {
				if ([item.name isEqualToString:@"path"]) {
					folderPath = item.value;
					break;
				}
			}
		}
		NSDictionary *folderContext = @{
			@"projectFolderSSID": projectFolderSSID ?: @"",
			@"folderURL": parentFolderVC.folder.url ?: @"",
			@"folderPath": folderPath ?: @"",
			@"folderName": parentFolderVC.folder.name ?: @""
		};
		[sharedDefaults setObject:folderContext forKey:@"SSCurrentFolder"];
	}
}

- (void)viewDidUnload {
	[super viewDidUnload];
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return YES;
}

#pragma mark -
- (id)initWithFilePreview:(FilePreview *) filePreview filename: (NSString *) filename {
	if (self = [super initWithAutoPlatformNibName]) {
		self.filePreview = filePreview;
		self.dataSource = self;
		self.title = filename;
	}
	return self;
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
	return self.filePreview ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
	if (index == 0 && self.filePreview) {
		return self.filePreview;
	}
	return nil;
}

@end

//
//  FolderViewController.m
//  SparkleShare
//
//  Created by Sergey Klimov on 13.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "FolderViewController.h"
#import "FileViewController.h"
#import "FileEditController.h"
#import "GitInfoFormatter.h"
#import "SSFolder.h"
#import "SSRootFolder.h"
#import "SSFile.h"
#import "SSFolderItem.h"
#import "FileSizeFormatter.h"
#import "UIColor+ApplicationColors.h"
#import "SVProgressHUD.h"
#import "UIViewController+AutoPlatformNibName.h"
#import "UIImage+FileType.h"
#import "SSRecentFile.h"
#import "SSRecentFilesManager.h"
#import "SparkleShareAppDelegate.h"
#import "SparkleShare-Swift.h"
#import <objc/runtime.h>

@interface FolderViewController ()
@property (nonatomic, strong) SSFile *pendingRecentFile;
@property (nonatomic, strong) NSMutableArray *pendingPathComponents;
@property (nonatomic, assign) NSInteger currentPathIndex;
@property (nonatomic, strong) UITapGestureRecognizer *editModeDismissGesture;
@end

@implementation FolderViewController
@synthesize folder = _folder, iconSize = _iconSize, recentFilesView = _recentFilesView;


- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationController.navigationBar.tintColor = [UIColor navBarColor];

	self.clearsSelectionOnViewWillAppear = NO;
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
        self.iconSize = 40*[[UIScreen mainScreen] scale];
    else
        self.iconSize = 40;

    // Refresh Control
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(reloadFolder) forControlEvents:UIControlEventValueChanged];
    [self setRefreshControl:refreshControl];

    self.restorationIdentifier = @"folderViewID";

    // Setup recent files view for root folder
    [self setupRecentFilesView];

    // Listen for recent files changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(recentFilesDidChange:)
                                                 name:SSRecentFilesDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupRecentFilesView {
    if ([self.folder isKindOfClass:[SSRootFolder class]]) {
        NSArray *recentFiles = [[SSRecentFilesManager sharedManager] recentFiles];
        if (recentFiles.count > 0) {
            self.recentFilesView = [[RecentFilesHostingView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 134)];
            self.recentFilesView.delegate = self;
            [self.recentFilesView updateWithRecentFiles:recentFiles];
            self.tableView.tableHeaderView = self.recentFilesView;
        }
    }
}

- (void)updateRecentFilesView {
    if ([self.folder isKindOfClass:[SSRootFolder class]]) {
        NSArray *recentFiles = [[SSRecentFilesManager sharedManager] recentFiles];
        if (recentFiles.count > 0) {
            if (!self.recentFilesView) {
                self.recentFilesView = [[RecentFilesHostingView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 134)];
                self.recentFilesView.delegate = self;
            }
            [self.recentFilesView updateWithRecentFiles:recentFiles];
            self.tableView.tableHeaderView = self.recentFilesView;
        } else {
            self.recentFilesView = nil;
            self.tableView.tableHeaderView = nil;
        }
    }
}

- (void)recentFilesDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateRecentFilesView];
    });
}

- (void)viewWillAppear: (BOOL) animated {
	[super viewWillAppear: animated];
	[SVProgressHUD show];
	[self.folder loadItems];
}

- (void)viewDidAppear: (BOOL) animated {
	[super viewDidAppear: animated];
}

- (void)viewWillDisappear: (BOOL) animated {
	[super viewWillDisappear: animated];
}

- (void)viewDidDisappear: (BOOL) animated {
	[super viewDidDisappear: animated];
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.folder.url  forKey:@"FolderPath"];
    [super encodeRestorableStateWithCoder:coder];
}

- (void)decodeRestorableStateWithCoder:(NSCoder *)coder {
    //NSLog([coder decodeObjectForKey:@"FolderPath"]);
    //TODO: recursively call didSelectRowAtIndexPath with path mapped to next part of indexPath,
    //pushing for each directory
    //could also just use userdefaults to restore
    [super decodeRestorableStateWithCoder:coder];
}

#pragma mark - Table view data source

// Customize the number of sections in the table view.
- (NSInteger)numberOfSectionsInTableView: (UITableView *) tableView {
	return 1;
}

- (NSInteger)tableView: (UITableView *) tableView numberOfRowsInSection: (NSInteger) section {
	return [self.folder.items count];
}

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView: (UITableView *) tableView cellForRowAtIndexPath: (NSIndexPath *) indexPath {
	static NSString *CellIdentifier = @"FolderCell";

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier: CellIdentifier];
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle: UITableViewCellStyleSubtitle reuseIdentifier: CellIdentifier];
	}

	SSFolderItem *item = [self.folder.items objectAtIndex: indexPath.row];
	cell.textLabel.text = item.name;
    
    //folder entries
	if ([item isKindOfClass: [SSFolder class]]) {
		if ([self.folder isKindOfClass: [SSRootFolder class]]) {
			cell.detailTextLabel.text = [NSString stringWithFormat: @"rev %@   %d items", [GitInfoFormatter stringFromGitRevision: ( (SSRootFolder *)item ).revision], ( (SSRootFolder *)item ).count];
		}
		else {
			cell.detailTextLabel.text = [NSString stringWithFormat: @"%d items", ( (SSFolder *)item ).count];
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
    //file entries
	else if ([item isKindOfClass: [SSFile class]]) {
		FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];
		NSString *sizeString = [sizeFormatter stringFromNumber: [NSNumber numberWithInt: ( (SSFile *)item ).filesize]];
		cell.detailTextLabel.text = [NSString stringWithFormat: @"%@  %@",
		                             ( (SSFile *)item ).mime, sizeString];
		cell.accessoryType = UITableViewCellAccessoryNone;
	}

    [cell.imageView setImage:[UIImage imageForMimeType:item.mime size:self.iconSize]];
    
	return cell;
}


#pragma mark - Table view delegate

- (void)tableView: (UITableView *) tableView didSelectRowAtIndexPath: (NSIndexPath *) indexPath {
	SSFolderItem *item = [self.folder.items objectAtIndex: indexPath.row];
    if (!item.completely_loaded) {
        return;
    }
	if ([item isKindOfClass: [SSFolder class]]) {
		FolderViewController *newFolderViewController = [[FolderViewController alloc] initWithFolder: (SSFolder *)item];
		[self.navigationController pushViewController: newFolderViewController animated: YES];
	}
	else if ([item isKindOfClass: [SSFile class]]) {
		SSFile *file = (SSFile *)item;
		file.delegate = self;
		[SVProgressHUD show];
		[file loadContent];
	}
}

#pragma mark - SSFolder stuff
- (id)initWithFolder: (SSFolder *) folder {
	if (self = [super initWithAutoPlatformNibName]) {
		self.folder = folder;
		self.folder.delegate = self;
		self.folder.infoDelegate = self;
		self.title = self.folder.name;
	}
	return self;
}

- (void) folder: (SSFolder *) folder itemsLoaded: (NSArray *) items {
	[self.tableView reloadData];
	for (SSFolderItem *item in self.folder.items) {
		if ([item isKindOfClass: [SSFolder class]]) {
			SSFolder *folder = (SSFolder *)item;
			folder.infoDelegate = self;
			[folder loadRevision];
			[folder loadCount];
		}
	}

    // Continue navigation if we're navigating to a recent file
    if (self.pendingPathComponents) {
        [self continueNavigationAfterFolderLoad];
    } else {
        [SVProgressHUD dismiss];
    }
    [self.refreshControl endRefreshing];
}

- (void) reloadOneItem: (SSFolderItem *) item {
	NSInteger i = [self.folder.items indexOfObject: item];
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow: i inSection: 0];

	[self.tableView reloadRowsAtIndexPaths: [NSArray arrayWithObject: indexPath] withRowAnimation: UITableViewRowAnimationNone];
}

//manually called refresh
- (void) reloadFolder {
	[SVProgressHUD show];
    
    [self.folder loadItems];
}

- (void) folderLoadingFailed: (SSFolder *) folder {
	[SVProgressHUD dismissWithError:@"Folder data loading failed"];
    [self.refreshControl endRefreshing];
}

- (void) folder: (SSFolder *) folder countLoaded: (int) count {
	[self reloadOneItem: folder];
}

- (void) folder: (SSFolder *) folder revisionLoaded: (NSString *) revision {
	[self reloadOneItem: folder];
}

- (void) folder: (SSFolder *) folder overallCountLoaded: (int) count {
	[self reloadOneItem: folder];
}

- (void) folderInfoLoadingFailed: (SSFolder *) folder {
}

- (void)fileContentLoaded: (SSFile *) file content: (NSData *) content {
    [SVProgressHUD dismiss];

    //override some text mime types that otherwise would not be displayed as text
    NSArray *overrideMime = @[@"application/x-tex",
                              @"application/x-latex",
                              @"application/javascript",
                              @"application/x-javascript",
                              @"application/mathematica"];
    if ([overrideMime containsObject: file.mime])
        file.mime = @"text/plain";

    //a lot of files are detected as octet-stream while they are text based
    if ([file.mime isEqualToString:@"application/octet-stream"]) {
        if ([file.name hasPrefix:@"."] ||
            [file.name hasSuffix:@".py"] ||
            [file.name hasSuffix:@".coffee"] ||
            [file.name hasSuffix:@".sci"] ||
            [file.name hasSuffix:@".rb"] ||
            [file.name hasSuffix:@".conf"] ||
            [file.name hasSuffix:@".plist"])
        {
            file.mime = @"text/plain";
        }
    }

    //override some file binary types that are detected as text
    if ([file.name hasSuffix:@".kdbx"]) {
        file.mime = @"application/octet-stream";
    }

    // Track this file as recently opened
    [self trackRecentFile:file];

    if( [file.mime hasPrefix:@"text/"] ) {
        //open text editing view if file is text
        FileEditController *newFileEditController = [[FileEditController alloc] initWithFile: file];
        [self.navigationController pushViewController: newFileEditController animated: YES];
    }  else {
        //otherwise preview file
        FilePreview *filePreview = [[FilePreview alloc] initWithFile: file];
        FileViewController *newFileViewController = [[FileViewController alloc] initWithFilePreview: filePreview filename: file.name];
    	[self.navigationController pushViewController: newFileViewController animated: YES];
    }
}

#pragma mark - Recent Files Tracking

- (void)trackRecentFile:(SSFile *)file {
    // Build path components from navigation stack
    // We skip the root folder and the project folder (stored separately)
    NSMutableArray *pathComponents = [NSMutableArray array];
    BOOL skippedProjectFolder = NO;

    for (UIViewController *vc in self.navigationController.viewControllers) {
        if ([vc isKindOfClass:[FolderViewController class]]) {
            FolderViewController *folderVC = (FolderViewController *)vc;
            SSFolder *folder = folderVC.folder;

            // Skip root folder
            if ([folder isKindOfClass:[SSRootFolder class]]) {
                continue;
            }

            // Skip the project folder (first non-root folder) - we store it separately
            if (!skippedProjectFolder) {
                skippedProjectFolder = YES;
                continue;
            }

            NSDictionary *component = @{
                @"name": folder.name ?: @"",
                @"ssid": folder.ssid ?: @"",
                @"type": folder.type ?: @""
            };
            [pathComponents addObject:component];
        }
    }

    // Get project folder info
    NSString *projectFolderSSID = file.projectFolder.ssid ?: @"";
    NSString *projectFolderName = file.projectFolder.name ?: @"";

    SSRecentFile *recentFile = [[SSRecentFile alloc] initWithFileName:file.name
                                                             fileSSID:file.ssid
                                                              fileURL:file.url
                                                             fileMime:file.mime
                                                             fileSize:file.filesize
                                                   projectFolderSSID:projectFolderSSID
                                                   projectFolderName:projectFolderName
                                                       pathComponents:pathComponents];

    [[SSRecentFilesManager sharedManager] addRecentFile:recentFile];
}

- (void) fileContentLoadingFailed: (SSFile *) file {
	[SVProgressHUD dismissWithError:@"File content loading failed"];
}

- (void)fileContentSaved: (SSFile *) file {
    [SVProgressHUD dismiss];
}

- (void) fileContentSavingFailed: (SSFile *) file error: (NSError *) error {
    [SVProgressHUD show];
    [SVProgressHUD dismissWithError:@"Saving file failed"];
    NSLog(@"Error %@", [error localizedRecoverySuggestion]);
}

#pragma mark - RecentFilesViewDelegate

- (void)recentFilesView:(UIView *)view didSelectRecentFile:(SSRecentFile *)recentFile {
    [self openRecentFile:recentFile];
}

- (void)recentFilesView:(UIView *)view didDeleteRecentFile:(SSRecentFile *)recentFile {
    [[SSRecentFilesManager sharedManager] removeRecentFile:recentFile];
}

- (void)recentFilesView:(UIView *)view didChangeEditMode:(BOOL)isEditMode {
    if (isEditMode) {
        // Add tap gesture to dismiss edit mode when tapping on table view
        if (!self.editModeDismissGesture) {
            self.editModeDismissGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissRecentFilesEditMode:)];
            self.editModeDismissGesture.cancelsTouchesInView = NO;
            [self.tableView addGestureRecognizer:self.editModeDismissGesture];
        }
    } else {
        // Remove tap gesture when exiting edit mode
        if (self.editModeDismissGesture) {
            [self.tableView removeGestureRecognizer:self.editModeDismissGesture];
            self.editModeDismissGesture = nil;
        }
    }
}

- (void)dismissRecentFilesEditMode:(UITapGestureRecognizer *)gesture {
    [self.recentFilesView exitEditMode];
}

#pragma mark - Recent Files Navigation

- (void)openRecentFile:(SSRecentFile *)recentFile {
    // Get root folder from app delegate
    SparkleShareAppDelegate *appDelegate = (SparkleShareAppDelegate *)[[UIApplication sharedApplication] delegate];
    SSConnection *conn = appDelegate.connection;
    SSRootFolder *rootFolder = conn.rootFolder;

    if (!rootFolder || !rootFolder.items) {
        [SVProgressHUD show];
        [SVProgressHUD dismissWithError:@"Connection not ready" afterDelay:1];
        return;
    }

    // Store pending file info
    self.pendingPathComponents = [recentFile.pathComponents mutableCopy];
    self.currentPathIndex = 0;

    // Store file metadata to reconstruct the file later
    NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
    fileInfo[@"name"] = recentFile.fileName ?: @"";
    fileInfo[@"ssid"] = recentFile.fileSSID ?: @"";
    fileInfo[@"url"] = recentFile.fileURL ?: @"";
    fileInfo[@"mime"] = recentFile.fileMime ?: @"";
    fileInfo[@"fileSize"] = @(recentFile.fileSize);
    fileInfo[@"projectFolderSSID"] = recentFile.projectFolderSSID ?: @"";
    fileInfo[@"projectFolderName"] = recentFile.projectFolderName ?: @"";

    // Pop to root first
    [self.navigationController popToRootViewControllerAnimated:NO];

    [SVProgressHUD show];

    // Start navigation through path
    FolderViewController *rootVC = self.navigationController.viewControllers.firstObject;
    if ([rootVC isKindOfClass:[FolderViewController class]]) {
        [rootVC navigateToRecentFileWithPathComponents:[recentFile.pathComponents mutableCopy]
                                           currentIndex:0
                                               fileInfo:fileInfo
                                     projectFolderSSID:recentFile.projectFolderSSID];
    }
}

- (void)navigateToRecentFileWithPathComponents:(NSMutableArray *)pathComponents
                                   currentIndex:(NSInteger)index
                                       fileInfo:(NSDictionary *)fileInfo
                             projectFolderSSID:(NSString *)projectFolderSSID {

    // First, find and navigate to the project folder
    if (index == 0) {
        // We're at root, find the project folder
        SSFolder *projectFolder = nil;
        NSString *projectFolderName = fileInfo[@"projectFolderName"];

        for (SSFolderItem *item in self.folder.items) {
            if ([item isKindOfClass:[SSFolder class]]) {
                // Try to match by name first
                if (projectFolderName && [item.name isEqualToString:projectFolderName]) {
                    projectFolder = (SSFolder *)item;
                    break;
                }
                // Fallback to SSID
                if ([item.ssid isEqualToString:projectFolderSSID]) {
                    projectFolder = (SSFolder *)item;
                    break;
                }
            }
        }

        if (!projectFolder) {
            [SVProgressHUD show];
            [SVProgressHUD dismissWithError:@"Project folder not found" afterDelay:1];
            return;
        }

        // Push project folder view controller
        FolderViewController *projectFolderVC = [[FolderViewController alloc] initWithFolder:projectFolder];
        [self.navigationController pushViewController:projectFolderVC animated:NO];

        // Continue navigation from project folder once it loads
        projectFolderVC.pendingPathComponents = pathComponents;
        projectFolderVC.currentPathIndex = 0;

        // Store file info for later use
        objc_setAssociatedObject(projectFolderVC, "pendingFileInfo", fileInfo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(projectFolderVC, "pendingProjectFolderSSID", projectFolderSSID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)continueNavigationAfterFolderLoad {
    NSDictionary *fileInfo = objc_getAssociatedObject(self, "pendingFileInfo");
    NSString *projectFolderSSID = objc_getAssociatedObject(self, "pendingProjectFolderSSID");

    if (!self.pendingPathComponents || !fileInfo) {
        [SVProgressHUD dismiss];
        [self clearPendingNavigation];
        return;
    }

    // If we've navigated through all path components, open the file
    if (self.currentPathIndex >= self.pendingPathComponents.count) {
        [self openFileFromInfo:fileInfo projectFolderSSID:projectFolderSSID];
        [self clearPendingNavigation];
        return;
    }

    // Find the next folder in the path
    NSDictionary *nextComponent = self.pendingPathComponents[self.currentPathIndex];
    NSString *folderSSID = nextComponent[@"ssid"];
    NSString *folderName = nextComponent[@"name"];

    SSFolder *nextFolder = nil;
    for (SSFolderItem *item in self.folder.items) {
        if ([item isKindOfClass:[SSFolder class]]) {
            // Try matching by name first
            if (folderName && [item.name isEqualToString:folderName]) {
                nextFolder = (SSFolder *)item;
                break;
            }
            if ([item.ssid isEqualToString:folderSSID]) {
                nextFolder = (SSFolder *)item;
                break;
            }
        }
    }

    if (!nextFolder) {
        [SVProgressHUD show];
        [SVProgressHUD dismissWithError:@"Path no longer exists" afterDelay:1];
        [self clearPendingNavigation];
        return;
    }

    // Push next folder view controller
    FolderViewController *nextVC = [[FolderViewController alloc] initWithFolder:nextFolder];
    [self.navigationController pushViewController:nextVC animated:NO];

    // Pass navigation state to new controller
    nextVC.pendingPathComponents = self.pendingPathComponents;
    nextVC.currentPathIndex = self.currentPathIndex + 1;
    objc_setAssociatedObject(nextVC, "pendingFileInfo", fileInfo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(nextVC, "pendingProjectFolderSSID", projectFolderSSID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self clearPendingNavigation];
}

- (void)openFileFromInfo:(NSDictionary *)fileInfo projectFolderSSID:(NSString *)projectFolderSSID {
    // Reconstruct the SSFile from stored metadata
    SparkleShareAppDelegate *appDelegate = (SparkleShareAppDelegate *)[[UIApplication sharedApplication] delegate];
    SSConnection *conn = appDelegate.connection;

    // Find project folder for this file
    SSFolder *projectFolder = nil;
    NSString *projectFolderName = fileInfo[@"projectFolderName"];

    for (SSFolderItem *item in conn.rootFolder.items) {
        if ([item isKindOfClass:[SSFolder class]]) {
            if (projectFolderName && [item.name isEqualToString:projectFolderName]) {
                projectFolder = (SSFolder *)item;
                break;
            }
            if ([item.ssid isEqualToString:projectFolderSSID]) {
                projectFolder = (SSFolder *)item;
                break;
            }
        }
    }

    if (!projectFolder) {
        projectFolder = self.folder.projectFolder;
    }

    // First, try to find the file in current folder's items
    SSFile *file = nil;
    NSString *fileSSID = fileInfo[@"ssid"];
    NSString *fileName = fileInfo[@"name"];

    for (SSFolderItem *item in self.folder.items) {
        if ([item isKindOfClass:[SSFile class]]) {
            if (fileName && [item.name isEqualToString:fileName]) {
                file = (SSFile *)item;
                break;
            }
            if ([item.ssid isEqualToString:fileSSID]) {
                file = (SSFile *)item;
                break;
            }
        }
    }

    if (!file) {
        [SVProgressHUD show];
        [SVProgressHUD dismissWithError:@"File not found" afterDelay:1];
        return;
    }

    // Load and open the file
    file.delegate = self;
    [file loadContent];
}

- (void)clearPendingNavigation {
    self.pendingPathComponents = nil;
    self.currentPathIndex = 0;
    objc_setAssociatedObject(self, "pendingFileInfo", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "pendingProjectFolderSSID", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

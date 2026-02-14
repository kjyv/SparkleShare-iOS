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
#import "SettingsViewController.h"
#import "SparkleShare-Swift.h"
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <PhotosUI/PhotosUI.h>

@interface FolderViewController () <RecentFilesViewDelegate, SSFolderItemsDelegate>
@property (nonatomic, strong) NSMutableArray *pendingPathComponents;
@property (nonatomic, assign) NSInteger currentPathIndex;
@property (nonatomic, strong) UITapGestureRecognizer *editModeDismissGesture;

// For recent file navigation - load in background, then set full stack
@property (nonatomic, strong) NSMutableArray<SSFolder *> *recentFilePathFolders;
@property (nonatomic, strong) NSDictionary *recentFileInfo;
@property (nonatomic, strong) SSFolder *currentlyLoadingFolder;
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

    // Add settings button for root folder, upload button for all other folders
    if ([self.folder isKindOfClass:[SSRootFolder class]]) {
        UIBarButtonItem *settingsButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                                                           style:UIBarButtonItemStylePlain
                                                                          target:self
                                                                          action:@selector(settingsPressed)];
        self.navigationItem.rightBarButtonItem = settingsButton;
    } else {
        UIAction *chooseFile = [UIAction actionWithTitle:@"Choose File"
                                                    image:[UIImage systemImageNamed:@"doc.badge.plus"]
                                               identifier:nil
                                                  handler:^(__kindof UIAction * _Nonnull action) {
            [self addFilePressed];
        }];
        UIAction *choosePhoto = [UIAction actionWithTitle:@"Choose Photo"
                                                    image:[UIImage systemImageNamed:@"photo.on.rectangle"]
                                               identifier:nil
                                                  handler:^(__kindof UIAction * _Nonnull action) {
            [self addPhotoPressed];
        }];
        UIMenu *addMenu = [UIMenu menuWithChildren:@[chooseFile, choosePhoto]];
        UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd menu:addMenu];
        self.navigationItem.rightBarButtonItem = addButton;
    }

    // Setup recent files view for root folder
    [self setupRecentFilesView];

    // Listen for recent files changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(recentFilesDidChange:)
                                                 name:SSRecentFilesDidChangeNotification
                                               object:nil];

}

- (void)settingsPressed {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    [self presentViewController:navController animated:YES completion:nil];
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
    // Check if this is a background load for recent file navigation
    if (folder == self.currentlyLoadingFolder) {
        [self folder:folder itemsLoadedForRecentFile:items];
        return;
    }

    // Normal folder display loading
	[self.tableView reloadData];
	for (SSFolderItem *item in self.folder.items) {
		if ([item isKindOfClass: [SSFolder class]]) {
			SSFolder *subFolder = (SSFolder *)item;
			subFolder.infoDelegate = self;
			[subFolder loadRevision];
			[subFolder loadCount];
		}
	}

    [SVProgressHUD dismiss];
    [self.refreshControl endRefreshing];

    // Re-open file if returning from share extension upload
    if (self.pendingReopenFilename) {
        NSString *filename = self.pendingReopenFilename;
        self.pendingReopenFilename = nil;

        // Pop the old FileViewController if it's still on top
        if ([self.navigationController.topViewController isKindOfClass:[FileViewController class]]) {
            [self.navigationController popViewControllerAnimated:NO];
        }

        // Find the file in the reloaded items and open it
        for (SSFolderItem *item in self.folder.items) {
            if ([item isKindOfClass:[SSFile class]] && [item.name isEqualToString:filename]) {
                SSFile *file = (SSFile *)item;
                file.delegate = self;
                [SVProgressHUD show];
                [file loadContent];
                break;
            }
        }
    }
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
    if (folder == self.currentlyLoadingFolder) {
        [self recentFileNavigationFailed:@"Folder loading failed"];
        return;
    }
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
    // Apply mime type overrides
    NSArray *overrideMime = @[@"application/x-tex",
                              @"application/x-latex",
                              @"application/javascript",
                              @"application/x-javascript",
                              @"application/mathematica"];
    if ([overrideMime containsObject:file.mime])
        file.mime = @"text/plain";

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

    if ([file.name hasSuffix:@".kdbx"]) {
        file.mime = @"application/octet-stream";
    }

    // Check if this is for recent file navigation
    if (self.recentFileInfo) {
        [self openRecentFileWithContent:file];
        return;
    }

    [SVProgressHUD dismiss];

    // Track this file as recently opened
    [self trackRecentFile:file];

    if ([file.mime hasPrefix:@"text/"]) {
        FileEditController *newFileEditController = [[FileEditController alloc] initWithFile:file];
        [self.navigationController pushViewController:newFileEditController animated:YES];
    } else {
        FilePreview *filePreview = [[FilePreview alloc] initWithFile:file];
        FileViewController *newFileViewController = [[FileViewController alloc] initWithFilePreview:filePreview filename:file.name];
        [self.navigationController pushViewController:newFileViewController animated:YES];
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
    if (self.recentFileInfo) {
        [self recentFileNavigationFailed:@"File content loading failed"];
        return;
    }
	[SVProgressHUD dismissWithError:@"File content loading failed"];
}

- (void)fileContentSaved: (SSFile *) file {
    [SVProgressHUD dismiss];
}

- (void) fileContentSavingFailed: (SSFile *) file error: (NSError *) error {
    [SVProgressHUD show];
    [SVProgressHUD dismissWithError:@"Saving file failed"];
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
        [SVProgressHUD dismissWithError:@"Connection not ready" afterDelay:1];
        return;
    }

    // Pop to root first
    [self.navigationController popToRootViewControllerAnimated:NO];

    [SVProgressHUD show];

    // Store file metadata
    NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
    fileInfo[@"name"] = recentFile.fileName ?: @"";
    fileInfo[@"ssid"] = recentFile.fileSSID ?: @"";
    fileInfo[@"url"] = recentFile.fileURL ?: @"";
    fileInfo[@"mime"] = recentFile.fileMime ?: @"";
    fileInfo[@"fileSize"] = @(recentFile.fileSize);
    fileInfo[@"projectFolderSSID"] = recentFile.projectFolderSSID ?: @"";
    fileInfo[@"projectFolderName"] = recentFile.projectFolderName ?: @"";

    // Start loading path in background from root
    FolderViewController *rootVC = self.navigationController.viewControllers.firstObject;
    if ([rootVC isKindOfClass:[FolderViewController class]]) {
        rootVC.recentFileInfo = fileInfo;
        rootVC.recentFilePathFolders = [NSMutableArray array];
        rootVC.pendingPathComponents = [recentFile.pathComponents mutableCopy];
        rootVC.currentPathIndex = 0;
        [rootVC startLoadingRecentFilePath];
    }
}

- (void)startLoadingRecentFilePath {
    // Find project folder first
    NSString *projectFolderName = self.recentFileInfo[@"projectFolderName"];
    NSString *projectFolderSSID = self.recentFileInfo[@"projectFolderSSID"];

    SSFolder *projectFolder = nil;
    for (SSFolderItem *item in self.folder.items) {
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
        [self recentFileNavigationFailed:@"Project folder not found"];
        return;
    }

    [self.recentFilePathFolders addObject:projectFolder];

    // If no subfolders in path, load file directly from project folder
    if (self.pendingPathComponents.count == 0) {
        [self loadRecentFileFromFinalFolder:projectFolder];
        return;
    }

    // Start loading the first subfolder
    self.currentPathIndex = 0;
    self.currentlyLoadingFolder = projectFolder;
    projectFolder.delegate = self;
    [projectFolder loadItems];
}

- (void)continueLoadingRecentFilePath {
    SSFolder *currentFolder = self.currentlyLoadingFolder;

    // Find next folder in path
    NSDictionary *nextComponent = self.pendingPathComponents[self.currentPathIndex];
    NSString *folderName = nextComponent[@"name"];
    NSString *folderSSID = nextComponent[@"ssid"];

    SSFolder *nextFolder = nil;
    for (SSFolderItem *item in currentFolder.items) {
        if ([item isKindOfClass:[SSFolder class]]) {
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
        [self recentFileNavigationFailed:@"Path no longer exists"];
        return;
    }

    [self.recentFilePathFolders addObject:nextFolder];
    self.currentPathIndex++;

    // If we've traversed all path components, load the file
    if (self.currentPathIndex >= self.pendingPathComponents.count) {
        [self loadRecentFileFromFinalFolder:nextFolder];
        return;
    }

    // Load next folder
    self.currentlyLoadingFolder = nextFolder;
    nextFolder.delegate = self;
    [nextFolder loadItems];
}

- (void)loadRecentFileFromFinalFolder:(SSFolder *)folder {
    // Load folder items to find the file
    self.currentlyLoadingFolder = folder;
    folder.delegate = self;
    [folder loadItems];
}

// SSFolderItemsDelegate for background folder loading
- (void)folder:(SSFolder *)folder itemsLoadedForRecentFile:(NSArray *)items {
    if (folder != self.currentlyLoadingFolder) {
        return; // Not our folder
    }

    // Check if we're still traversing path or at final folder
    if (self.currentPathIndex < self.pendingPathComponents.count) {
        [self continueLoadingRecentFilePath];
    } else {
        // At final folder - find and load file
        [self findAndLoadRecentFile];
    }
}

- (void)findAndLoadRecentFile {
    SSFolder *finalFolder = self.currentlyLoadingFolder;
    NSString *fileName = self.recentFileInfo[@"name"];
    NSString *fileSSID = self.recentFileInfo[@"ssid"];

    SSFile *file = nil;
    for (SSFolderItem *item in finalFolder.items) {
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
        [self recentFileNavigationFailed:@"File not found"];
        return;
    }

    // Load file content
    file.delegate = self;
    [file loadContent];
}

- (void)recentFileNavigationFailed:(NSString *)message {
    self.recentFileInfo = nil;
    self.recentFilePathFolders = nil;
    self.pendingPathComponents = nil;
    self.currentlyLoadingFolder = nil;
    [SVProgressHUD dismissWithError:message afterDelay:1];
}

- (void)openRecentFileWithContent:(SSFile *)file {
    [SVProgressHUD dismiss];

    // Build the full navigation stack
    NSMutableArray *viewControllers = [NSMutableArray array];

    // Add root (self)
    [viewControllers addObject:self];

    // Add folder view controllers for each folder in path
    for (SSFolder *folder in self.recentFilePathFolders) {
        FolderViewController *folderVC = [[FolderViewController alloc] initWithFolder:folder];
        [viewControllers addObject:folderVC];
    }

    // Track file as recently opened (from the parent folder VC)
    FolderViewController *parentFolderVC = [viewControllers lastObject];

    // Create file view controller
    UIViewController *fileVC;
    if ([file.mime hasPrefix:@"text/"]) {
        fileVC = [[FileEditController alloc] initWithFile:file];
    } else {
        FilePreview *filePreview = [[FilePreview alloc] initWithFile:file];
        fileVC = [[FileViewController alloc] initWithFilePreview:filePreview filename:file.name];
    }
    [viewControllers addObject:fileVC];

    // Set entire navigation stack at once
    [self.navigationController setViewControllers:viewControllers animated:YES];

    // Track as recent file
    [parentFolderVC trackRecentFile:file];

    // Clear state
    self.recentFileInfo = nil;
    self.recentFilePathFolders = nil;
    self.pendingPathComponents = nil;
    self.currentlyLoadingFolder = nil;
}

#pragma mark - File Upload

- (void)uploadFileData:(NSData *)data filename:(NSString *)filename {
    // Extract folder path from self.folder.url query parameters
    NSString *folderPath = nil;
    if (self.folder.url) {
        NSURLComponents *components = [NSURLComponents componentsWithString:
            [NSString stringWithFormat:@"http://localhost/?%@", self.folder.url]];
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"path"]) {
                folderPath = item.value;
                break;
            }
        }
    }

    // Build the new file path
    NSString *newFilePath;
    if (folderPath) {
        newFilePath = [NSString stringWithFormat:@"%@/%@", folderPath, filename];
    } else {
        newFilePath = filename;
    }

    // Encode for query string values (/ must become %2F)
    NSMutableCharacterSet *valueChars = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [valueChars removeCharactersInString:@"/?&=+"];
    NSString *encodedPath = [newFilePath stringByAddingPercentEncodingWithAllowedCharacters:valueChars];
    NSString *encodedName = [filename stringByAddingPercentEncodingWithAllowedCharacters:valueChars];

    NSString *uploadPath = [NSString stringWithFormat:@"/api/postFile/%@?path=%@&name=%@",
        self.folder.projectFolder.ssid, encodedPath, encodedName];

    SparkleShareAppDelegate *appDelegate = (SparkleShareAppDelegate *)[[UIApplication sharedApplication] delegate];
    SSConnection *conn = appDelegate.connection;

    [SVProgressHUD showWithStatus:@"Uploading..."];
    [conn uploadBinaryData:data toPath:uploadPath success:^{
        [SVProgressHUD dismissWithSuccess:@"Uploaded!"];
        [self reloadFolder];
    } failure:^(NSError *error) {
        NSString *errorMsg = [NSString stringWithFormat:@"Upload failed: %@", error.localizedDescription];
        [SVProgressHUD dismissWithError:errorMsg afterDelay:3];
    }];
}

- (void)addFilePressed {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem]];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    BOOL accessing = [url startAccessingSecurityScopedResource];
    NSData *fileData = [NSData dataWithContentsOfURL:url];
    if (accessing) {
        [url stopAccessingSecurityScopedResource];
    }

    if (!fileData) {
        [SVProgressHUD dismissWithError:@"Could not read file" afterDelay:2];
        return;
    }

    [self uploadFileData:fileData filename:url.lastPathComponent];
}

#pragma mark - Photo Upload

- (void)addPhotoPressed {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.selectionLimit = 1;
    config.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[
        [PHPickerFilter imagesFilter],
        [PHPickerFilter videosFilter]
    ]];
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];

    PHPickerResult *result = results.firstObject;
    if (!result) return;

    NSItemProvider *provider = result.itemProvider;

    // Use loadFileRepresentationForTypeIdentifier to get a temp file with original filename
    [provider loadFileRepresentationForTypeIdentifier:UTTypeItem.identifier completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
        if (!url) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *msg = error ? [NSString stringWithFormat:@"Could not load photo: %@", error.localizedDescription] : @"Could not load photo";
                [SVProgressHUD dismissWithError:msg afterDelay:2];
            });
            return;
        }

        NSData *data = [NSData dataWithContentsOfURL:url];
        NSString *filename = url.lastPathComponent;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!data) {
                [SVProgressHUD dismissWithError:@"Could not read photo data" afterDelay:2];
                return;
            }
            [self uploadFileData:data filename:filename];
        });
    }];
}

@end

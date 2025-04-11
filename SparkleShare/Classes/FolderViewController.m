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

@implementation FolderViewController
@synthesize folder = _folder, iconSize = _iconSize;


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
	[SVProgressHUD dismiss];
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


@end

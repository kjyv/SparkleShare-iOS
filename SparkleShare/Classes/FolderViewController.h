//
//  FolderViewController.h
//  SparkleShare
//
//  Created by Sergey Klimov on 13.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SSFolder.h"
#import "SSFile.h"

@class SSRecentFile;
@class RecentFilesHostingView;

@interface FolderViewController : UITableViewController <SSFolderInfoDelegate, SSFolderItemsDelegate, SSFileDelegate> {
}

@property (strong) SSFolder *folder;
@property int iconSize;
@property (strong) RecentFilesHostingView *recentFilesView;

- (id)initWithFolder: (SSFolder *) folder;
- (void)reloadFolder;

// Opens a recent file by navigating through its path
- (void)openRecentFile:(SSRecentFile *)recentFile;

@end
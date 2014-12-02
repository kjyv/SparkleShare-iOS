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
#import "EGORefreshTableHeaderView.h"

@interface FolderViewController : UITableViewController <EGORefreshTableHeaderDelegate, SSFolderInfoDelegate, SSFolderItemsDelegate, SSFileDelegate> {

    EGORefreshTableHeaderView *_refreshHeaderView;
    BOOL _reloading;
}

@property (strong) SSFolder *folder;
@property int iconSize;

- (id)initWithFolder: (SSFolder *) folder;
- (void)reloadTableViewDataSource;
- (void)doneLoadingTableViewData;

@end
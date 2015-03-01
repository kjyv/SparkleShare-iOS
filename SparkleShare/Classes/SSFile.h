//
//  SSFile.h
//  SparkleShare
//
//  Created by Sergey Klimov on 07.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "SSFolderItem.h"

@class SSFile;
@protocol SSFileDelegate <NSObject>
- (void)fileContentLoaded: (SSFile *) file content: (NSData *) content;
- (void)fileContentLoadingFailed: (SSFile *) file;
- (void)fileContentSaved: (SSFile *) file;
- (void)fileContentSavingFailed: (SSFile *) file error: (NSError *) error;
@end


@interface SSFile : SSFolderItem

- (id)initWithConnection: (SSConnection *) aConnection
       name: (NSString *) aName
       ssid: (NSString *) anId
       url: (NSString *) anUrl
       projectFolder: (SSFolder *) projectFolder
       mime: (NSString *) mime
       filesize: (int) filesize;


@property (strong) NSData *content;
@property int filesize;
@property (weak) id <SSFileDelegate> delegate;
- (void)loadContent;
- (void)saveContent: (NSString *) text;
@end
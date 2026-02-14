//
//  FilePreview.h
//  SparkleShare
//
//  Created by Sergey Klimov on 13.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>
@class SSFile;
@interface FilePreview : NSObject <QLPreviewItem>
- (id)initWithFile: (SSFile *) file;
- (id)initWithURL:(NSURL *)url filename:(NSString *)filename;
@property (copy) NSString *filename;
@property (copy) NSURL *localURL;
@property (copy) NSString *fileAPIURL;
@property (copy) NSString *projectFolderSSID;

@end
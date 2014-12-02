//
//  FilePreview.m
//  SparkleShare
//
//  Created by Sergey Klimov on 13.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "FilePreview.h"
#import "SSFile.h"
#import "NSString+Hashing.h"

@implementation FilePreview
@synthesize filename = _filename, localURL = _localURL;
- (id) initWithFile: (SSFile *) file {
	if (self = [super init]) {
		self.filename = file.name;
		NSString *path = [NSTemporaryDirectory () stringByAppendingPathComponent: [file.url sha1]];
		NSError *error;
		if (![[NSFileManager defaultManager] fileExistsAtPath: path]) { //Does directory already exist?
			if (![[NSFileManager defaultManager] createDirectoryAtPath: path
			      withIntermediateDirectories: NO
			      attributes: nil
			      error: &error]) {
				self = nil;
				return self;
			}
		}

		NSString *tempFileName = [path stringByAppendingPathComponent: self.filename];

		if (![[NSFileManager defaultManager] createFileAtPath: tempFileName
		      contents: file.content
		      attributes: nil]) {
			self = nil;
			return self;
		}
		else {
			self.localURL = [NSURL fileURLWithPath: tempFileName];
            //reencode text files which QLPreviewController seems to only be able to display
            //properly with utf16 encoding
            if( [file.mime isEqualToString:@"text/plain"] ) {                
                if( [[[NSString alloc] initWithData:file.content encoding:NSUTF8StringEncoding] writeToURL:self.localURL atomically:YES encoding:NSUTF16StringEncoding error:&error] )
                {
                    // Continue presenting the QLPreviewController from localFileURL
                }
                else
                {
                    NSLog( @"An error occured: %@", error );
                }
            }
		}
	}

	return self;
}

- (NSURL *) previewItemURL {
	return self.localURL;
}

- (NSString *) previewItemTitle {
	return self.filename;
}

@end
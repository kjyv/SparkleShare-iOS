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

- (id)initWithURL:(NSURL *)url filename:(NSString *)filename {
	if (self = [super init]) {
		self.localURL = url;
		self.filename = filename;
	}
	return self;
}

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
            //reencode text files since QLPreviewController seems to only be able to
            //display them properly with utf16 encoding
            //Note: might give problems with really large text files...
            if( [file.mime isEqualToString:@"text/plain"] ) {
                if( ![[[NSString alloc] initWithData:file.content encoding:NSUTF8StringEncoding] writeToURL:self.localURL atomically:YES encoding:NSUTF16StringEncoding error:&error] )
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

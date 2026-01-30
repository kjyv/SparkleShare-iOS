//
//  SSRecentFile.m
//  SparkleShare
//
//  Data model for storing recently opened file metadata.
//

#import "SSRecentFile.h"

@implementation SSRecentFile

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithFileName:(NSString *)fileName
                        fileSSID:(NSString *)fileSSID
                         fileURL:(NSString *)fileURL
                        fileMime:(NSString *)fileMime
                        fileSize:(int)fileSize
              projectFolderSSID:(NSString *)projectFolderSSID
              projectFolderName:(NSString *)projectFolderName
                  pathComponents:(NSArray<NSDictionary *> *)pathComponents {
    self = [super init];
    if (self) {
        _fileName = [fileName copy];
        _fileSSID = [fileSSID copy];
        _fileURL = [fileURL copy];
        _fileMime = [fileMime copy];
        _fileSize = fileSize;
        _projectFolderSSID = [projectFolderSSID copy];
        _projectFolderName = [projectFolderName copy];
        _pathComponents = [pathComponents copy];
        _accessDate = [NSDate date];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _fileName = [coder decodeObjectOfClass:[NSString class] forKey:@"fileName"];
        _fileSSID = [coder decodeObjectOfClass:[NSString class] forKey:@"fileSSID"];
        _fileURL = [coder decodeObjectOfClass:[NSString class] forKey:@"fileURL"];
        _fileMime = [coder decodeObjectOfClass:[NSString class] forKey:@"fileMime"];
        _fileSize = [coder decodeIntForKey:@"fileSize"];
        _projectFolderSSID = [coder decodeObjectOfClass:[NSString class] forKey:@"projectFolderSSID"];
        _projectFolderName = [coder decodeObjectOfClass:[NSString class] forKey:@"projectFolderName"];

        NSSet *allowedClasses = [NSSet setWithObjects:[NSArray class], [NSDictionary class], [NSString class], [NSNumber class], nil];
        _pathComponents = [coder decodeObjectOfClasses:allowedClasses forKey:@"pathComponents"];

        _accessDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"accessDate"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_fileName forKey:@"fileName"];
    [coder encodeObject:_fileSSID forKey:@"fileSSID"];
    [coder encodeObject:_fileURL forKey:@"fileURL"];
    [coder encodeObject:_fileMime forKey:@"fileMime"];
    [coder encodeInt:_fileSize forKey:@"fileSize"];
    [coder encodeObject:_projectFolderSSID forKey:@"projectFolderSSID"];
    [coder encodeObject:_projectFolderName forKey:@"projectFolderName"];
    [coder encodeObject:_pathComponents forKey:@"pathComponents"];
    [coder encodeObject:_accessDate forKey:@"accessDate"];
}

@end

//
//  SSRecentFile.h
//  SparkleShare
//
//  Data model for storing recently opened file metadata.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSRecentFile : NSObject <NSSecureCoding>

// File properties
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *fileSSID;
@property (nonatomic, copy) NSString *fileURL;
@property (nonatomic, copy) NSString *fileMime;
@property (nonatomic, assign) int fileSize;

// Project folder info
@property (nonatomic, copy) NSString *projectFolderSSID;
@property (nonatomic, copy) NSString *projectFolderName;

// Path components from root to parent folder
// Each element is a dictionary with keys: name, ssid, type
@property (nonatomic, copy) NSArray<NSDictionary *> *pathComponents;

// Access timestamp for sorting
@property (nonatomic, strong) NSDate *accessDate;

- (instancetype)initWithFileName:(NSString *)fileName
                        fileSSID:(NSString *)fileSSID
                         fileURL:(NSString *)fileURL
                        fileMime:(NSString *)fileMime
                        fileSize:(int)fileSize
              projectFolderSSID:(NSString *)projectFolderSSID
              projectFolderName:(NSString *)projectFolderName
                  pathComponents:(NSArray<NSDictionary *> *)pathComponents;

@end

NS_ASSUME_NONNULL_END

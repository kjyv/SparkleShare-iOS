//
//  SSRecentFilesManager.h
//  SparkleShare
//
//  Singleton manager for recently opened files persistence.
//

#import <Foundation/Foundation.h>

@class SSRecentFile;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SSRecentFilesDidChangeNotification;

@interface SSRecentFilesManager : NSObject

@property (class, readonly, strong) SSRecentFilesManager *sharedManager;

// Returns recent files sorted by accessDate descending (most recent first)
- (NSArray<SSRecentFile *> *)recentFiles;

// Adds or updates a recent file (updates if ssid matches existing)
- (void)addRecentFile:(SSRecentFile *)recentFile;

// Removes a specific recent file by matching its logical path
- (void)removeRecentFile:(SSRecentFile *)recentFile;

// Clears all recent files
- (void)clearRecentFiles;

@end

NS_ASSUME_NONNULL_END

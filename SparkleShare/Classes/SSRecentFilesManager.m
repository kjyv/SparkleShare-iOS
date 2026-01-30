//
//  SSRecentFilesManager.m
//  SparkleShare
//
//  Singleton manager for recently opened files persistence.
//

#import "SSRecentFilesManager.h"
#import "SSRecentFile.h"

NSString * const SSRecentFilesDidChangeNotification = @"SSRecentFilesDidChangeNotification";

static NSString * const kRecentFilesKey = @"SSRecentFiles";
static const NSInteger kMaxRecentFiles = 10;

@interface SSRecentFilesManager ()
@property (nonatomic, strong) NSMutableArray<SSRecentFile *> *mutableRecentFiles;
@end

@implementation SSRecentFilesManager

+ (SSRecentFilesManager *)sharedManager {
    static SSRecentFilesManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[SSRecentFilesManager alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadRecentFiles];
    }
    return self;
}

- (void)loadRecentFiles {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kRecentFilesKey];
    if (data) {
        NSError *error = nil;
        NSSet *allowedClasses = [NSSet setWithObjects:[NSArray class], [SSRecentFile class], nil];
        NSArray *decoded = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowedClasses fromData:data error:&error];
        if (decoded && !error) {
            self.mutableRecentFiles = [decoded mutableCopy];
        } else {
            self.mutableRecentFiles = [NSMutableArray array];
        }
    } else {
        self.mutableRecentFiles = [NSMutableArray array];
    }
}

- (void)saveRecentFiles {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.mutableRecentFiles requiringSecureCoding:YES error:&error];
    if (data && !error) {
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:kRecentFilesKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (NSArray<SSRecentFile *> *)recentFiles {
    // Return sorted by accessDate descending
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"accessDate" ascending:NO];
    return [self.mutableRecentFiles sortedArrayUsingDescriptors:@[sortDescriptor]];
}

// Generate a unique key based on file path (not hash-based SSID which changes on commits)
- (NSString *)uniqueKeyForRecentFile:(SSRecentFile *)recentFile {
    NSMutableString *key = [NSMutableString string];

    // Project folder name
    [key appendString:recentFile.projectFolderName ?: @""];
    [key appendString:@"/"];

    // Path components (folder names)
    for (NSDictionary *component in recentFile.pathComponents) {
        NSString *name = component[@"name"];
        if (name) {
            [key appendString:name];
            [key appendString:@"/"];
        }
    }

    // File name
    [key appendString:recentFile.fileName ?: @""];

    return key;
}

- (void)addRecentFile:(SSRecentFile *)recentFile {
    // Remove existing entry with same logical path (not SSID, which changes on commits)
    NSString *newKey = [self uniqueKeyForRecentFile:recentFile];
    NSMutableArray *toRemove = [NSMutableArray array];
    for (SSRecentFile *existing in self.mutableRecentFiles) {
        NSString *existingKey = [self uniqueKeyForRecentFile:existing];
        if ([existingKey isEqualToString:newKey]) {
            [toRemove addObject:existing];
        }
    }
    [self.mutableRecentFiles removeObjectsInArray:toRemove];

    // Add new entry at beginning
    [self.mutableRecentFiles insertObject:recentFile atIndex:0];

    // Trim to max size
    while (self.mutableRecentFiles.count > kMaxRecentFiles) {
        [self.mutableRecentFiles removeLastObject];
    }

    [self saveRecentFiles];
    [[NSNotificationCenter defaultCenter] postNotificationName:SSRecentFilesDidChangeNotification object:self];
}

- (void)removeRecentFile:(SSRecentFile *)recentFile {
    NSString *keyToRemove = [self uniqueKeyForRecentFile:recentFile];
    NSMutableArray *toRemove = [NSMutableArray array];
    for (SSRecentFile *existing in self.mutableRecentFiles) {
        NSString *existingKey = [self uniqueKeyForRecentFile:existing];
        if ([existingKey isEqualToString:keyToRemove]) {
            [toRemove addObject:existing];
        }
    }
    [self.mutableRecentFiles removeObjectsInArray:toRemove];

    [self saveRecentFiles];
    [[NSNotificationCenter defaultCenter] postNotificationName:SSRecentFilesDidChangeNotification object:self];
}

- (void)clearRecentFiles {
    [self.mutableRecentFiles removeAllObjects];
    [self saveRecentFiles];
    [[NSNotificationCenter defaultCenter] postNotificationName:SSRecentFilesDidChangeNotification object:self];
}

@end

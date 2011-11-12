//
//  SSConnection.h
//  SparkleShare
//
//  Created by Sergey Klimov on 07.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@class SSConnection;

@protocol SSConnectionDelegate <NSObject>
-(void) connectionEstablishingSuccess:(SSConnection*) connection;
-(void) connectionEstablishingFailed:(SSConnection*) connection;
@end

@protocol SSConnectionFoldersDelegate <NSObject>
-(void) connection:(SSConnection*) connection foldersLoaded:(NSArray*) folders;
-(void) connectionFoldersLoadingFailed:(SSConnection*) connection;
@end


@interface SSConnection : NSObject
{
@private
    NSURL* address;
    NSString* identCode;
    NSString* authCode;
    NSOperationQueue *queue;

}

@property (weak) id<SSConnectionDelegate> delegate;
@property (weak) id<SSConnectionFoldersDelegate> foldersDelegate;
@property (strong) NSArray* folders;

-(id) initWithAddress:(NSURL*)anAddress identCode:(NSString*)anIdentCode authCode:(NSString*)anAuthCode;
-(id) initWithUserDefaults;
-(void) sendRequestWithString:(NSString*) string 
                      success:(void (^)(NSURLRequest *request, NSURLResponse *response, id JSON))success 
                      failure:(void (^)(NSURLRequest *request, NSURLResponse *response, NSError *error, id JSON))failure;
-(void) linkDeviceWithAddress:(NSURL*)anAddress code:(NSString*)aCode;
-(void) loadFolders;
@end

//
//  SSConnection.h
//  SparkleShare
//
//  Created by Sergey Klimov on 07.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@class SSConnection;
@class SSRootFolder;

@protocol SSConnectionDelegate <NSObject>
- (void)connectionEstablishingSuccess: (SSConnection *) connection;
- (void)connectionEstablishingFailed: (SSConnection *) connection;
- (void)connectionLinkingSuccess: (SSConnection *) connection;
- (void)connectionLinkingFailed: (SSConnection *) connection error: (NSString*) error;
@end


@interface SSConnection : NSObject
{
	@private
	NSURL *address;
	NSString *identCode;
	NSString *authCode;
	NSOperationQueue *queue;
}

@property (weak) id <SSConnectionDelegate> delegate;
@property (strong) SSRootFolder *rootFolder;

- (id)initWithUserDefaults;
- (void)establishConnection;
- (void)sendRequestWithString: (NSString *) string
       success: ( void (^)(NSURLRequest * request, NSURLResponse * response, id JSON) ) success
       failure: ( void (^)(NSURLRequest * request, NSURLResponse * response, NSError * error, id JSON) ) failure;
- (void) sendPostRequestWithStringAndData:(NSString *)string data: (NSString *)data
       success: ( void (^)(NSURLRequest * request, NSURLResponse * response, id JSON))success
       failure: ( void (^)(NSURLRequest * request, NSURLResponse * response, NSError * error, id JSON))failure;
- (void)linkDeviceWithAddress: (NSURL *) anAddress code: (NSString *) aCode;
@end

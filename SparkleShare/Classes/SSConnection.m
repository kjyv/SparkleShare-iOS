//
//  SSConnection.m
//  SparkleShare
//
//  Created by Sergey Klimov on 07.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "SSConnection.h"
#import "SSJSONRequestOperation.h"
#import "SSRootFolder.h"

@interface SSConnection ()

@property (readwrite) NSString *identCode;
@property (readwrite) NSString *authCode;
@property (readwrite) NSURL *address;

- (void) testConnection;

@end

@implementation SSConnection
@synthesize identCode, authCode, address;
@synthesize delegate = _delegate, rootFolder = _rootFolder;

- (id) init {
	if (self = [super init]) {
		queue = [[NSOperationQueue alloc] init];
	}
	return self;
}

- (id) initWithAddress: (NSURL *) anAddress identCode: (NSString *) anIdentCode authCode: (NSString *) anAuthCode {
	if (self = [self init]) {
        address = anAddress;
        authCode = anAuthCode;
        identCode = anIdentCode;
    }
	return self;
}

- (id) initWithUserDefaults {
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	if ((![userDefaults URLForKey: @"link"])||([userDefaults boolForKey:@"resetAuthEnabled"])) {
		self = [self init];
        
        if ([userDefaults boolForKey:@"resetAuthEnabled"]) {
            [userDefaults setBool:NO forKey:@"resetAuthEnabled"];
            [userDefaults removeObjectForKey:@"link"];
            [userDefaults removeObjectForKey:@"authCode"];
            [userDefaults removeObjectForKey:@"identCode"];
            [userDefaults synchronize];
        }
	}
	else {
		self = [self initWithAddress: [userDefaults URLForKey: @"link"] identCode: [userDefaults objectForKey: @"identCode"] authCode: [userDefaults objectForKey: @"authCode"]];   
    }
    
	return self;
}

- (void) establishConnection {
    if (!self.address) {
        [self.delegate connectionEstablishingFailed:self];
    }
    else {
        [self testConnection];
    }
}

//$ curl --data "code=286685&name=My%20Name" http://localhost:3000/api/getAuthCode
//{"ident":"qj7cGswA","authCode":"iteLARuURXKzGNJ...solGzbOutrWcfOWaUnm7ZIgNyn-"}
- (void) linkDeviceWithAddress: (NSURL *) anAddress code: (NSString *) code {
	address = anAddress;
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [address URLByAppendingPathComponent:  @"api/getAuthCode"]];
	[request setHTTPMethod: @"POST"];
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *deviceName = [userDefaults stringForKey:@"customDeviceName"] ?: [[UIDevice currentDevice] name];
    
    NSString *encodedCode = [code stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *encodedName = [deviceName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];

    NSString *requestString = [NSString stringWithFormat:@"code=%@&name=%@", encodedCode, encodedName];
    NSData *requestData = [requestString dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:requestData];
    [request setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

	SSJSONRequestOperation *operation = [SSJSONRequestOperation JSONRequestOperationWithRequest: request success:^(NSURLRequest * request, NSURLResponse * response, id JSON) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
            if ([JSON isKindOfClass:[NSString class]]) {
                [self.delegate connectionLinkingFailed:self error: JSON];
            }
            else if (httpResponse.statusCode == 404 || httpResponse.statusCode == 500) {
                [self.delegate connectionLinkingFailed:self error: [NSString stringWithFormat:@"Unable to connect to Server URL (error code: %ld).", (long)httpResponse.statusCode]];
            } else {
                self->identCode = [JSON valueForKey: @"ident"];
                self->authCode = [JSON valueForKey: @"authCode"];
                [userDefaults setObject: self->identCode forKey: @"identCode"];
                [userDefaults setObject: self->authCode forKey: @"authCode"];
                [userDefaults setURL: self->address forKey: @"link"];
                [userDefaults setBool: YES forKey: @"linked"];
                [userDefaults removeObjectForKey: @"code"];
                
                [userDefaults synchronize];
                [self.delegate connectionLinkingSuccess:self];
                [self testConnection];
            }
         }
         failure:^(NSURLRequest *request, NSURLResponse *response, NSError *error, id JSON) {
             NSLog(@"JSON Request error: %@", error);
             //errors:
             //-1012 if certificate is invalid (expired? or self signed)
             //(-1012 generally means kCFURLErrorUserCancelledAuthentication
             //-1011 if return code != 200-299
             //-1200 if some ats ssl error has happened
             
             if (error.code == -1012) {
                 [self.delegate connectionLinkingFailed:self error: @"Unable to connect to Server URL. The SSL certificate might be invalid. Consider importing it manually if it is self-signed."];
             } else if (error.code == -1011 && ((NSHTTPURLResponse *)response).statusCode == 403) {
                 [self.delegate connectionLinkingFailed:self error: @"Unable to connect to Server URL. The link code was not accepted."];
             } else {
                 [self.delegate connectionLinkingFailed:self error: [error description]];
             }
         }
	];

	[queue addOperation: operation];
}


- (void) sendRequestWithString: (NSString *) string
        success: ( void (^)(NSURLRequest * request, NSURLResponse * response, id JSON) ) success
        failure: ( void (^)(NSURLRequest * request, NSURLResponse * response, NSError * error, id JSON) ) failure {
	NSString *urlRequest = [[address absoluteString] stringByAppendingString: string];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: urlRequest]];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData];
	[request setValue: identCode forHTTPHeaderField: @"X-SPARKLE-IDENT"];
	[request setValue: authCode forHTTPHeaderField: @"X-SPARKLE-AUTH"];

	SSJSONRequestOperation *operation = [SSJSONRequestOperation JSONRequestOperationWithRequest: request success: success failure: failure];

	[queue addOperation: operation];
}

- (void) sendPostRequestWithStringAndData:(NSString *)string data: (NSString *)data
        success: ( void (^)(NSURLRequest * request, NSURLResponse * response, id JSON) ) success
        failure: ( void (^)(NSURLRequest * request, NSURLResponse * response, NSError * error, id JSON) ) failure {
    //expects a string data with form of "key=value&key2=..."
    NSString *urlRequest = [[address absoluteString] stringByAppendingString: string];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: urlRequest]];
    [request setValue: identCode forHTTPHeaderField: @"X-SPARKLE-IDENT"];
    [request setValue: authCode forHTTPHeaderField: @"X-SPARKLE-AUTH"];
    [request setHTTPMethod:@"POST"];
    [request addValue: @"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    
    NSData *encodedData = [data dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody: encodedData];    

    [request setTimeoutInterval:60];
    
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        success(operation.request, operation.response, responseObject);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        failure(operation.request, operation.response, error, operation.responseObject);
    }];
    
    [queue addOperation: operation];
}

- (void) testConnection {
	[self sendRequestWithString: @"/api/ping"
	 success:
	 ^(NSURLRequest * request, NSURLResponse * response, id JSON) {
         if ([@"pong" isEqual: JSON]) {
             self.rootFolder = [[SSRootFolder alloc] initWithConnection: self];
             [self.delegate connectionEstablishingSuccess: self];
		 } else {
             [self.delegate connectionEstablishingFailed: self];
		 }
	 }
	 failure:
	 ^(NSURLRequest * request, NSURLResponse * response, NSError * error, id JSON) {
         [self.delegate connectionEstablishingFailed: self];
	 }
	];
}

- (NSMutableURLRequest *)requestForPath:(NSString *)path {
    NSString *urlRequest = [[address absoluteString] stringByAppendingString:path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlRequest]];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData];
    [request setValue:identCode forHTTPHeaderField:@"X-SPARKLE-IDENT"];
    [request setValue:authCode forHTTPHeaderField:@"X-SPARKLE-AUTH"];
    return request;
}

- (void)addOperation:(NSOperation *)operation {
    [queue addOperation:operation];
}

@end

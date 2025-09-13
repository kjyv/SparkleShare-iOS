//
//  SSJSONRequestOperation.m
//  SparkleShare
//
//  Created by Sergey Klimov on 13.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "SSJSONRequestOperation.h"

@implementation SSJSONRequestOperation

+ (instancetype)JSONRequestOperationWithRequest:(NSURLRequest *)urlRequest
                                        success:(void (^)(NSURLRequest *request, NSURLResponse *response, id JSON))success
                                        failure:(void (^)(NSURLRequest *request, NSURLResponse *response, NSError *error, id JSON))failure
{
    SSJSONRequestOperation *requestOperation = [(SSJSONRequestOperation *)[self alloc] initWithRequest:urlRequest];
    
    AFJSONResponseSerializer *serializer = [AFJSONResponseSerializer serializer];
    serializer.readingOptions = NSJSONReadingAllowFragments;
    requestOperation.responseSerializer = serializer;
    
    [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (success) {
            success(operation.request, operation.response, responseObject);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (failure) {
            failure(operation.request, operation.response, error, operation.responseObject);
        }
    }];
    
    return requestOperation;
}

@end
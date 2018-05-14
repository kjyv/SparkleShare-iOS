//
//  NSString+urlencode.m
//  SparkleShare
//
//  Created by Stefan Bethge on 14.05.18.
//

#import <Foundation/Foundation.h>

@implementation NSString (NSString_urlencoding)

- (NSString *)urlencode {
    static NSMutableCharacterSet *chars = nil;
    static dispatch_once_t pred;
    
    if (chars)
        return [self stringByAddingPercentEncodingWithAllowedCharacters:chars];
    
    // to be thread safe
    dispatch_once(&pred, ^{
        chars = NSCharacterSet.URLQueryAllowedCharacterSet.mutableCopy;
        [chars removeCharactersInString:@"!*'();:@&=+$,/?%#[]"];
    });
    return [self stringByAddingPercentEncodingWithAllowedCharacters:chars];
}
@end

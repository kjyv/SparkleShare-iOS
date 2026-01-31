//
//  SSWebView.m
//  SparkleShare
//
//  WKWebView subclass that hides the input accessory view.
//

#import "SSWebView.h"

@implementation SSWebView

- (UIView *)inputAccessoryView {
    return nil;
}

@end

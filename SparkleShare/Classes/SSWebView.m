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

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    // Only allow basic text editing actions, no formatting
    if (action == @selector(cut:) ||
        action == @selector(copy:) ||
        action == @selector(paste:) ||
        action == @selector(select:) ||
        action == @selector(selectAll:)) {
        return [super canPerformAction:action withSender:sender];
    }

    // Block all other actions (formatting, etc.)
    return NO;
}

@end

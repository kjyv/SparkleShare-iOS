//
//  FileEditController.h
//  SparkleShare
//
//  Created by Stefan Bethge on 12.12.14.
//
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "SSFile.h"
#import "UIViewController+AutoPlatformNibName.h"

@interface FileEditController : UIViewController <UITextViewDelegate, WKNavigationDelegate> {
    bool fileChanged;
    CGRect _oldRect;
    NSTimer* _caretVisibilityTimer;
    UITextRange *_selectedRange;
    CGPoint offset;
    BOOL _isPreviewMode;
};
- (id)initWithFile: (SSFile *) file;

@property (weak) SSFile *file;
@property (weak, nonatomic) IBOutlet UITextView *textEditView;
@property (strong, nonatomic) WKWebView *webView;
@property (assign, nonatomic) BOOL isMarkdownFile;

@end

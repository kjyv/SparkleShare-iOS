//
//  FileEditController.h
//  SparkleShare
//
//  Created by Stefan Bethge on 12.12.14.
//
//

#import <UIKit/UIKit.h>
#import "SSFile.h"
#import "UIViewController+AutoPlatformNibName.h"

@class MarkdownHostingView;

@interface FileEditController : UIViewController <UITextViewDelegate> {
    bool fileChanged;
    BOOL _isPreviewMode;
    BOOL _initialRenderDone;
}
- (id)initWithFile: (SSFile *) file;

@property (weak) SSFile *file;
@property (weak, nonatomic) IBOutlet UITextView *textEditView;
@property (strong, nonatomic) MarkdownHostingView *markdownView;
@property (assign, nonatomic) BOOL isMarkdownFile;

@end

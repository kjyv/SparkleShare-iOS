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

@interface FileEditController : UIViewController <UITextViewDelegate> {
    bool fileChanged;
};
- (id)initWithFile: (SSFile *) file;

@property (weak) SSFile *file;
@property (weak, nonatomic) IBOutlet UITextView *textEditView;


@end

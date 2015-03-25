//
//  FileEditController.m
//  SparkleShare
//
//  Created by Stefan Bethge on 12.12.14.
//
//

#import <Foundation/Foundation.h>
#import "FileEditController.h"
#import "SSFile.h"
#import "NSString+Hashing.h"
#import "SVProgressHUD.h"

@implementation FileEditController
@synthesize textEditView;
@synthesize file = _file;

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //TODO: improve loading the text, could be different encodings, binary, too large etc.
    [textEditView setText:[[NSString alloc] initWithData:_file.content encoding:NSUTF8StringEncoding]];
    
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
        name:UIKeyboardWillShowNotification object:nil];
/*    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidShow:)
         name:UIKeyboardDidShowNotification object:nil];*/

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
        name:UIKeyboardWillHideNotification object:nil];
/*    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidHide:)
        name:UIKeyboardDidHideNotification object:nil];*/

}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewDidUnload {
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation) interfaceOrientation {
    return YES;
}

#pragma mark - keyboard movements

- (void)keyboardWillShow:(NSNotification *)notification
{
    UIEdgeInsets insets = self.textEditView.contentInset;
    insets.bottom = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
    self.textEditView.contentInset = insets;
    
    insets = self.textEditView.scrollIndicatorInsets;
    insets.bottom = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
    self.textEditView.scrollIndicatorInsets = insets;
  
    self.textEditView.selectedTextRange = _selectedRange;
}

-(void)keyboardWillHide:(NSNotification *)notification
{
    UIEdgeInsets insets = self.textEditView.contentInset;
//    insets.bottom -= [notification.userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue].size.height;
//    if (insets.bottom < 0)
        insets.bottom = 0;
    self.textEditView.contentInset = insets;
    
    insets = self.textEditView.scrollIndicatorInsets;
//    insets.bottom -= [notification.userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue].size.height;
//    if (insets.bottom < 0)
        insets.bottom = 0;
    self.textEditView.scrollIndicatorInsets = insets;
}


- (void)setEditing:(BOOL)flag animated:(BOOL)animated
{
    [super setEditing:flag animated:animated];
    if (flag == YES){
        //make view editable
        offset = self.textEditView.contentOffset;
        [textEditView setEditable:true];
        [[NSOperationQueue mainQueue] addOperationWithBlock: ^{
            [self.textEditView setContentOffset: offset];
        }];

    }
    else {
        [textEditView setEditable:false];
                
        //save changes
        if (fileChanged) {
            [SVProgressHUD showWithStatus:@"Saving" networkIndicator:true];
            [_file saveContent: textEditView.text];            
            fileChanged = false;
        }
    }
}


#pragma mark -

- (id)initWithFile: (SSFile *) file {
    if (self = [super initWithAutoPlatformNibName]) {
        _file = file;
    }
    fileChanged = false;
    return self;
}

#pragma mark - TextView

- (void)textViewDidChangeSelection:(UITextView *)textView {
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
    //[NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(_scrollToCaret) userInfo:nil repeats:NO];

    /*_oldRect = [self.textEditView caretRectForPosition:self.textEditView.selectedTextRange.end];
    
    _caretVisibilityTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(_scrollCaretToVisible) userInfo:nil repeats:YES];*/
    _selectedRange = textEditView.selectedTextRange;
}

- (void)textViewDidChange:(UITextView *)textView {
    fileChanged = true;
}

- (void)textViewDidEndEditing:(UITextView *)textView {
/*    [_caretVisibilityTimer invalidate];
    _caretVisibilityTimer = nil;*/
}

//TODO check landscape
//TODO other files after first seem to use old values for the first time

- (void)_scrollToCaret {
    [self.textEditView scrollRangeToVisible:self.textEditView.selectedRange];
}

- (void)_scrollCaretToVisible
{
    //This is where the cursor is at.
    CGRect caretRect = [self.textEditView caretRectForPosition:self.textEditView.selectedTextRange.end];

    // Convert into the correct coordinate system
    caretRect = [self.view convertRect:caretRect fromView:self.textEditView];

    if(CGRectEqualToRect(caretRect, _oldRect))
        return;
    
    _oldRect = caretRect;
    
    //This is the visible rect of the textview.
    CGRect visibleRect = self.textEditView.frame;
    //visibleRect.size.height -= (self.textEditView.contentInset.top + self.textEditView.contentInset.bottom);
    //visibleRect.origin.y = self.textEditView.contentOffset.y;
    
    //We will scroll only if the caret falls outside of the visible rect.
    if(!CGRectContainsRect(visibleRect, caretRect))
    {
        CGPoint newOffset = self.textEditView.contentOffset;
        
        //newOffset.y = MAX((caretRect.origin.y + caretRect.size.height) - visibleRect.size.height + 5 + 20, 0);
        newOffset.y += MAX((caretRect.origin.y + caretRect.size.height) - (visibleRect.origin.y + visibleRect.size.height) + self.textEditView.font.lineHeight*2, 0);
        [self.textEditView setContentOffset:newOffset animated:YES];
    }
    [_caretVisibilityTimer invalidate];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
//
//  FileEditController.m
//  SparkleShare
//
//  Created by Stefan Bethge on 12.12.14.
//
//

#import "FileEditController.h"
#import "SSFile.h"
#import "NSString+Hashing.h"
#import "SVProgressHUD.h"
#import <WebKit/WebKit.h>
#import <MMMarkdown/MMMarkdown.h>

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
    
    if (self.isMarkdownFile) {
        // Initialize WKWebView only for markdown files
        self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds];
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.webView.navigationDelegate = self;
        [self.view addSubview:self.webView];
        [self.view sendSubviewToBack:self.webView]; // Ensure webView is behind textEditView initially

        // Initial state: Preview mode for markdown files
        _isPreviewMode = YES; 
        self.textEditView.hidden = YES;
        self.webView.hidden = NO;
        [self renderMarkdownToWebView];
    } else {
        // For non-markdown files, always show textEditView
        _isPreviewMode = NO;
        self.textEditView.hidden = NO;
    }

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

#pragma mark - Markdown Rendering

- (void)renderMarkdownToWebView {
    NSError *error = nil;
    NSString *markdownContent = self.textEditView.text;
    NSString *htmlString = [MMMarkdown HTMLStringWithMarkdown:markdownContent error:&error];

    if (htmlString && !error) {
        // Get system colors for both bright and dark mode
        UIColor *brightSystemBackgroundColor = [UIColor systemBackgroundColor];
        UIColor *brightLabelColor = [UIColor labelColor];
        
        // For dark mode, these will be different
        UIColor *darkSystemBackgroundColor = [UIColor systemBackgroundColor]; // Will be dark in dark mode
        UIColor *darkLabelColor = [UIColor labelColor]; // Will be light in dark mode

        NSString *brightBgColorRGBA = [self rgbaStringFromColor:brightSystemBackgroundColor];
        NSString *brightTextColorRGBA = [self rgbaStringFromColor:brightLabelColor];
        NSString *darkBgColorRGBA = [self rgbaStringFromColor:darkSystemBackgroundColor];
        NSString *darkTextColorRGBA = [self rgbaStringFromColor:darkLabelColor];

        // Inject CSS for larger font size and dynamic bright/dark mode colors
        NSString *css = [NSString stringWithFormat:@"<style>body { font-size: 40px; background-color: %@; color: %@; } @media (prefers-color-scheme: dark) { body { background-color: %@; color: %@; } }</style>", brightBgColorRGBA, brightTextColorRGBA, darkBgColorRGBA, darkTextColorRGBA];
        NSString *finalHtmlString = [NSString stringWithFormat:@"%@%@", css, htmlString];
        [self.webView loadHTMLString:finalHtmlString baseURL:nil];
    } else {
        NSLog(@"Error rendering markdown to HTML: %@", error);
        [self.webView loadHTMLString:@"<h1>Error rendering markdown</h1>" baseURL:nil];
    }
}

#pragma mark - keyboard movements

- (void)keyboardWillShow:(NSNotification *)notification
{
    // Only adjust for keyboard if in edit mode
    if (!_isPreviewMode) {
        //push up content by keyboard size
        UIEdgeInsets insets = self.textEditView.contentInset;
        insets.bottom = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
        self.textEditView.contentInset = insets;
        
        //push up scroll indicator by keyboard size
        insets = self.textEditView.verticalScrollIndicatorInsets;
        insets.bottom = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
        self.textEditView.verticalScrollIndicatorInsets = insets;
    }
}

-(void)keyboardWillHide:(NSNotification *)notification
{
    if (!_isPreviewMode) {
        UIEdgeInsets insets = self.textEditView.contentInset;
        insets.bottom = 0;
        self.textEditView.contentInset = insets;
        
        insets = self.textEditView.verticalScrollIndicatorInsets;
        insets.bottom = 0;
        self.textEditView.verticalScrollIndicatorInsets = insets;
    }
}


- (void)setEditing:(BOOL)flag animated:(BOOL)animated
{
    [super setEditing:flag animated:animated];
    if (self.isMarkdownFile) {
        if (flag == YES){
            // Entering Edit Mode
            _isPreviewMode = NO;
            self.textEditView.hidden = NO;
            self.webView.hidden = YES;
            [textEditView setEditable:true];
            
            // Reset content insets and scroll to top to ensure correct positioning
            self.textEditView.contentInset = UIEdgeInsetsZero;
            self.textEditView.scrollIndicatorInsets = UIEdgeInsetsZero;
            [self.textEditView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];

        }
        else {
            // Exiting Edit Mode (and potentially saving)
            _isPreviewMode = YES;
            self.textEditView.hidden = YES;
            self.webView.hidden = NO;
            [textEditView setEditable:false];
            [self renderMarkdownToWebView]; // Render updated markdown
                    
            //save changes
            if (fileChanged) {
                [SVProgressHUD showWithStatus:@"Saving" networkIndicator:true];
                [_file saveContent: textEditView.text];
                fileChanged = false;
            }
        }
    } else {
        // For non-markdown files, just handle editing state without preview logic
        if (flag == YES) {
            [textEditView setEditable:true];
        } else {
            [textEditView setEditable:false];
            //save changes
            if (fileChanged) {
                [SVProgressHUD showWithStatus:@"Saving" networkIndicator:true];
                [_file saveContent: textEditView.text];
                fileChanged = false;
            }
        }
    }
}


#pragma mark -

- (id)initWithFile: (SSFile *) file {
    if (self = [super initWithAutoPlatformNibName]) {
        _file = file;
        _isPreviewMode = NO; // Default to edit mode, will be overridden in viewDidLoad
        
        // Determine if the file is markdown based on MIME type
        self.isMarkdownFile = NO;
        if ([file.mime isEqualToString:@"text/markdown"] ||
            [file.mime isEqualToString:@"text/x-markdown"]) {
            self.isMarkdownFile = YES;
        } else if ([file.mime isEqualToString:@"text/plain"]) {
            // As a fallback, check extension for plain text files
            if ([file.name.pathExtension isEqualToString:@"md"] ||
                [file.name.pathExtension isEqualToString:@"markdown"]) {
                self.isMarkdownFile = YES;
            }
        }
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

// Helper to convert UIColor to rgba() string
- (NSString *)rgbaStringFromColor:(UIColor *)color {
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"rgba(%.0f, %.0f, %.0f, %.2f)", r * 255, g * 255, b * 255, a];
}

@end

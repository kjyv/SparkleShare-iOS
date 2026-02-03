//
//  FileEditController.m
//  SparkleShare
//
//  Created by Stefan Bethge on 12.12.14.
//
//
//  ============================================================================
//  MARKDOWN VIEWER WITH SWIFTUI RENDERING
//  ============================================================================
//
//  This controller provides two modes for text files:
//  1. Traditional edit mode (UITextView) - for plain text and full-document editing
//  2. Read-only preview mode (SwiftUI) - for markdown files with native rendering
//
//  For markdown files:
//  - Preview mode shows rendered markdown using native SwiftUI components
//  - Task list checkboxes are interactive and can be toggled
//  - Edit button switches to full UITextView editing
//
//  For non-markdown text files:
//  - Direct UITextView editing as before
//
//  ============================================================================

#import "FileEditController.h"
#import "SSFile.h"
#import "SVProgressHUD.h"
#import "SparkleShare-Swift.h"

@interface FileEditController () <MarkdownViewDelegate>
@end

@implementation FileEditController
@synthesize textEditView;
@synthesize file = _file;

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    [textEditView setText:[[NSString alloc] initWithData:_file.content encoding:NSUTF8StringEncoding]];

    self.navigationItem.rightBarButtonItem = self.editButtonItem;

    [self updateBackButton];

    if (self.isMarkdownFile) {
        // Initialize SwiftUI markdown view with Auto Layout
        self.markdownView = [[MarkdownHostingView alloc] initWithFrame:CGRectZero];
        self.markdownView.translatesAutoresizingMaskIntoConstraints = NO;
        self.markdownView.delegate = self;
        [self.view addSubview:self.markdownView];
        [self.view sendSubviewToBack:self.markdownView];

        // Constrain to safe area
        [NSLayoutConstraint activateConstraints:@[
            [self.markdownView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [self.markdownView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.markdownView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.markdownView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];

        // Initial state: Preview mode for markdown files
        _isPreviewMode = YES;
        self.textEditView.hidden = YES;
        self.markdownView.hidden = NO;
        // Render will happen in viewDidAppear after layout is complete
    } else {
        // For non-markdown files, always show textEditView
        _isPreviewMode = NO;
        self.textEditView.hidden = NO;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
        name:UIKeyboardWillShowNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
        name:UIKeyboardWillHideNotification object:nil];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Render markdown after layout is complete to ensure correct scroll position
    if (self.isMarkdownFile && !_initialRenderDone) {
        _initialRenderDone = YES;
        [self renderMarkdownToView];
    }
}

- (void)handleBackButton {
    // If in traditional edit mode (Edit button), cancel and restore
    if (self.editing) {
        [self cancelEditing];
        return;
    }

    // Otherwise, navigate back to parent
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)cancelEditing {
    fileChanged = NO;

    // Exit traditional edit mode if active
    if (self.editing) {
        [super setEditing:NO animated:YES];
    }

    // Return to preview mode for markdown files
    if (self.isMarkdownFile) {
        _isPreviewMode = YES;
        self.textEditView.hidden = YES;
        self.markdownView.hidden = NO;
        [textEditView setEditable:NO];
        [self renderMarkdownToView];
    }

    [self updateBackButton];
}

- (void)updateBackButton {
    if (self.editing) {
        // Show Cancel button when in traditional edit mode
        NSBundle *uiKitBundle = [NSBundle bundleForClass:[UIButton class]];
        NSString *cancelTitle = [uiKitBundle localizedStringForKey:@"Cancel" value:@"Cancel" table:nil];
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:cancelTitle
                                                                         style:UIBarButtonItemStylePlain
                                                                        target:self
                                                                        action:@selector(handleBackButton)];
        self.navigationItem.leftBarButtonItem = cancelButton;
    } else {
        // Show back button with chevron
        UIImage *chevron = [UIImage systemImageNamed:@"chevron.left"];
        UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithImage:chevron
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(handleBackButton)];
        self.navigationItem.leftBarButtonItem = backButton;
    }
}

#pragma mark - Markdown Rendering

- (void)renderMarkdownToView {
    NSString *markdownContent = self.textEditView.text;
    [self.markdownView updateWithMarkdown:markdownContent];
}

#pragma mark - MarkdownViewDelegate

- (void)markdownView:(UIView *)view didToggleCheckboxAtIndex:(NSInteger)index checked:(BOOL)checked {
    [self toggleCheckboxAtIndex:index toChecked:checked];
}

- (void)toggleCheckboxAtIndex:(NSInteger)index toChecked:(BOOL)checked {
    NSString *markdown = self.textEditView.text;
    NSMutableString *result = [NSMutableString string];

    // Find the nth checkbox pattern in the markdown
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"- \\[([ xX])\\]"
                                                                           options:0
                                                                             error:nil];
    NSArray *matches = [regex matchesInString:markdown options:0 range:NSMakeRange(0, markdown.length)];

    if (index < (NSInteger)matches.count) {
        NSTextCheckingResult *match = matches[index];
        NSRange checkboxRange = [match rangeAtIndex:1]; // The space or x inside [ ]

        // Build the new string
        [result appendString:[markdown substringToIndex:checkboxRange.location]];
        [result appendString:checked ? @"x" : @" "];
        [result appendString:[markdown substringFromIndex:checkboxRange.location + checkboxRange.length]];

        // Update the text view
        self.textEditView.text = result;
        fileChanged = YES;

        // Save immediately
        [_file saveContent:self.textEditView.text];

        // Re-render the markdown view
        [self renderMarkdownToView];
    }
}

#pragma mark - keyboard movements

- (void)keyboardWillShow:(NSNotification *)notification
{
    // Only adjust for keyboard if in edit mode
    if (!_isPreviewMode) {
        UIEdgeInsets insets = self.textEditView.contentInset;
        insets.bottom = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
        self.textEditView.contentInset = insets;

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
            self.markdownView.hidden = YES;
            [textEditView setEditable:true];

            // Reset content insets and scroll to top to ensure correct positioning
            self.textEditView.contentInset = UIEdgeInsetsZero;
            self.textEditView.scrollIndicatorInsets = UIEdgeInsetsZero;
            [self.textEditView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];

            [self updateBackButton];
        }
        else {
            // Exiting Edit Mode (and potentially saving)
            _isPreviewMode = YES;
            self.textEditView.hidden = YES;
            self.markdownView.hidden = NO;
            [textEditView setEditable:false];
            [self renderMarkdownToView];

            if (fileChanged) {
                [SVProgressHUD showWithStatus:@"Saving" networkIndicator:true];
                [_file saveContent:textEditView.text];
                fileChanged = false;
            }

            [self updateBackButton];
        }
    } else {
        // For non-markdown files, just handle editing state without preview logic
        if (flag == YES) {
            [textEditView setEditable:true];
            [self updateBackButton];
        } else {
            [textEditView setEditable:false];
            if (fileChanged) {
                [SVProgressHUD showWithStatus:@"Saving" networkIndicator:true];
                [_file saveContent:textEditView.text];
                fileChanged = false;
            }
            [self updateBackButton];
        }
    }
}

#pragma mark -

- (id)initWithFile: (SSFile *) file {
    if (self = [super initWithAutoPlatformNibName]) {
        _file = file;
        _isPreviewMode = NO;

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

- (void)textViewDidChange:(UITextView *)textView {
    fileChanged = true;
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

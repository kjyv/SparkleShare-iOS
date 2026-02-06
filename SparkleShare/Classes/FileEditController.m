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

    // Fix textEditView to start below the nav bar (XIB pins to topMargin=0)
    NSMutableArray *toDeactivate = [NSMutableArray array];
    for (NSLayoutConstraint *constraint in self.view.constraints) {
        BOOL matchesFirst = constraint.firstItem == self.textEditView &&
            (constraint.firstAttribute == NSLayoutAttributeTop ||
             constraint.firstAttribute == NSLayoutAttributeCenterY);
        BOOL matchesSecond = constraint.secondItem == self.textEditView &&
            (constraint.secondAttribute == NSLayoutAttributeTop ||
             constraint.secondAttribute == NSLayoutAttributeCenterY);
        if (matchesFirst || matchesSecond) {
            [toDeactivate addObject:constraint];
        }
    }
    [NSLayoutConstraint deactivateConstraints:toDeactivate];
    [NSLayoutConstraint activateConstraints:@[
        [self.textEditView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textEditView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    UIImage *editImage = [UIImage systemImageNamed:@"doc.plaintext"];
    UIBarButtonItem *editButton = [[UIBarButtonItem alloc] initWithImage:editImage
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(toggleEditing)];
    self.navigationItem.rightBarButtonItem = editButton;

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

- (void)toggleEditing {
    [self setEditing:!self.editing animated:YES];
}

- (void)updateEditButton {
    NSString *imageName = self.editing ? @"checkmark" : @"doc.plaintext";
    self.navigationItem.rightBarButtonItem.image = [UIImage systemImageNamed:imageName];
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
        [self updateEditButton];
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

- (void)markdownView:(UIView *)view didFinishEditingAtStartLine:(NSInteger)startLine
             endLine:(NSInteger)endLine newText:(NSString *)newText {
    if (newText.length == 0) {
        // Empty text - delete the lines entirely (paragraph/heading removed)
        NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
        NSMutableArray *result = [NSMutableArray array];
        for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
            if (i < startLine - 1 || i >= endLine) {
                [result addObject:lines[i]];
            }
        }
        self.textEditView.text = [result componentsJoinedByString:@"\n"];
        fileChanged = YES;

        // Start editing the previous line (the line above the deleted one)
        if (startLine > 1) {
            [self.markdownView setPendingEditingLine:startLine - 1];
        }
    } else {
        [self replaceLines:startLine toLine:endLine withText:newText];
    }

    [_file saveContent:self.textEditView.text];
    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didInsertLineAfterStartLine:(NSInteger)startLine
             endLine:(NSInteger)endLine textBefore:(NSString *)textBefore textAfter:(NSString *)textAfter {
    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSMutableArray *result = [NSMutableArray array];

    // Lines before the paragraph (lines 0 to startLine-2, which is indices 0 to startLine-2)
    for (NSInteger i = 0; i < startLine - 1; i++) {
        [result addObject:lines[i]];
    }

    // Add the edited content (textBefore may contain multiple lines)
    [result addObjectsFromArray:[textBefore componentsSeparatedByString:@"\n"]];

    // Insert new line(s) with textAfter (textAfter may also contain multiple lines)
    [result addObjectsFromArray:[textAfter componentsSeparatedByString:@"\n"]];

    // Lines after the paragraph (starting from endLine, which is index endLine)
    for (NSInteger i = endLine; i < (NSInteger)lines.count; i++) {
        [result addObject:lines[i]];
    }

    self.textEditView.text = [result componentsJoinedByString:@"\n"];
    fileChanged = YES;

    [_file saveContent:self.textEditView.text];

    // Calculate where the new line (textAfter) starts and set it for editing
    NSInteger textBeforeLineCount = [[textBefore componentsSeparatedByString:@"\n"] count];
    NSInteger newEditLine = startLine + textBeforeLineCount;
    [self.markdownView setPendingEditingLine:newEditLine];

    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didRequestMergeLineAtStart:(NSInteger)startLine
             endLine:(NSInteger)endLine currentText:(NSString *)currentText {
    if (startLine <= 1) return; // Can't merge first paragraph

    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSMutableArray *result = [NSMutableArray array];

    // Use the actual edited text (not stale file content) for the current paragraph
    NSArray *currentLines = [currentText componentsSeparatedByString:@"\n"];
    NSString *prevLine = (startLine >= 2 && startLine - 2 < (NSInteger)lines.count) ? lines[startLine - 2] : @"";
    NSString *currentFirstLine = currentLines.count > 0 ? currentLines[0] : @"";
    NSString *merged = [NSString stringWithFormat:@"%@%@", prevLine, currentFirstLine];

    // Lines before the previous line
    for (NSInteger i = 0; i < startLine - 2; i++) {
        [result addObject:lines[i]];
    }

    // Add merged line
    [result addObject:merged];

    // Add rest of current edited text (if multi-line)
    for (NSInteger i = 1; i < (NSInteger)currentLines.count; i++) {
        [result addObject:currentLines[i]];
    }

    // Lines after the original paragraph
    for (NSInteger i = endLine; i < (NSInteger)lines.count; i++) {
        [result addObject:lines[i]];
    }

    self.textEditView.text = [result componentsJoinedByString:@"\n"];
    fileChanged = YES;
    [_file saveContent:self.textEditView.text];

    // Continue editing the merged line
    [self.markdownView setPendingEditingLine:startLine - 1];
    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didInsertTextAtEmptyLine:(NSInteger)lineNumber
             newText:(NSString *)newText {
    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSMutableArray *result = [NSMutableArray array];

    // Lines before the empty line (indices 0 to lineNumber-2)
    for (NSInteger i = 0; i < lineNumber - 1; i++) {
        [result addObject:lines[i]];
    }

    // Insert the new text at the empty line position (may be multiple lines)
    [result addObjectsFromArray:[newText componentsSeparatedByString:@"\n"]];

    // Lines after the empty line (starting from index lineNumber, which was the next line)
    for (NSInteger i = lineNumber; i < (NSInteger)lines.count; i++) {
        [result addObject:lines[i]];
    }

    self.textEditView.text = [result componentsJoinedByString:@"\n"];
    fileChanged = YES;
    [_file saveContent:self.textEditView.text];
    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didDeleteEmptyLine:(NSInteger)lineNumber {
    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSMutableArray *result = [NSMutableArray array];

    // Add all lines except the one at lineNumber
    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        if (i != lineNumber - 1) { // lineNumber is 1-based, i is 0-based
            [result addObject:lines[i]];
        }
    }

    self.textEditView.text = [result componentsJoinedByString:@"\n"];
    fileChanged = YES;
    [_file saveContent:self.textEditView.text];

    // Try to stay in edit mode - prefer the previous line (above), then current position (below)
    NSInteger nextEditLine = 0;

    // First try the previous line (the one above)
    if (lineNumber > 1) {
        NSString *prevLineContent = result[lineNumber - 2]; // lineNumber-1 is current, lineNumber-2 is previous (0-indexed)
        if ([prevLineContent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
            nextEditLine = lineNumber - 1;
        }
    }

    // If previous line wasn't empty, try the current position (which is now what was below)
    if (nextEditLine == 0 && lineNumber <= (NSInteger)result.count) {
        NSString *currLineContent = result[lineNumber - 1]; // 0-indexed
        if ([currLineContent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
            nextEditLine = lineNumber;
        }
    }

    if (nextEditLine > 0) {
        [self.markdownView setPendingEditingLine:nextEditLine];
    }

    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didSplitEmptyLine:(NSInteger)lineNumber
          textBefore:(NSString *)textBefore textAfter:(NSString *)textAfter {
    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSMutableArray *result = [NSMutableArray array];

    // Lines before the empty line (indices 0 to lineNumber-2)
    for (NSInteger i = 0; i < lineNumber - 1; i++) {
        [result addObject:lines[i]];
    }

    // Add the text before cursor (replaces the empty line)
    NSArray *textBeforeLines = [textBefore componentsSeparatedByString:@"\n"];
    [result addObjectsFromArray:textBeforeLines];

    // Track where the new empty line will be
    NSInteger newEmptyLineNumber = result.count + 1;

    // Add a new empty line (the split point)
    [result addObject:@""];

    // Add the text after cursor (if any)
    if (textAfter.length > 0) {
        // textAfter starts with \n from the cursor position, split and add
        NSArray *afterLines = [textAfter componentsSeparatedByString:@"\n"];
        // Skip the first empty element if textAfter started with \n
        for (NSInteger i = (afterLines.count > 0 && [afterLines[0] length] == 0) ? 1 : 0; i < (NSInteger)afterLines.count; i++) {
            [result addObject:afterLines[i]];
        }
    }

    // Lines after the original empty line (starting from index lineNumber)
    for (NSInteger i = lineNumber; i < (NSInteger)lines.count; i++) {
        [result addObject:lines[i]];
    }

    self.textEditView.text = [result componentsJoinedByString:@"\n"];
    fileChanged = YES;
    [_file saveContent:self.textEditView.text];

    // Stay in edit mode on the new empty line
    [self.markdownView setPendingEditingLine:newEmptyLineNumber];

    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didMergeEmptyLineWithPrevious:(NSInteger)lineNumber
                text:(NSString *)text {
    if (lineNumber <= 1) return; // Can't merge with line before first line

    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSMutableArray *result = [NSMutableArray array];

    // Lines before the previous line
    for (NSInteger i = 0; i < lineNumber - 2; i++) {
        [result addObject:lines[i]];
    }

    // Merge: previous line content + text from current line
    NSString *prevLine = (lineNumber >= 2 && lineNumber - 2 < (NSInteger)lines.count) ? lines[lineNumber - 2] : @"";
    NSString *merged = [NSString stringWithFormat:@"%@%@", prevLine, text];
    [result addObject:merged];

    // The merged line is now at position lineNumber - 1
    NSInteger mergedLineNumber = lineNumber - 1;

    // Skip the current line (it's merged), add rest
    for (NSInteger i = lineNumber; i < (NSInteger)lines.count; i++) {
        [result addObject:lines[i]];
    }

    self.textEditView.text = [result componentsJoinedByString:@"\n"];
    fileChanged = YES;
    [_file saveContent:self.textEditView.text];

    // Check if the merged line is empty (to stay in empty line edit mode)
    if ([merged stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
        [self.markdownView setPendingEditingLine:mergedLineNumber];
    }

    [self renderMarkdownToView];
}

#pragma mark - Line Operations

- (void)replaceLines:(NSInteger)startLine toLine:(NSInteger)endLine withText:(NSString *)newText {
    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSMutableArray *result = [NSMutableArray array];

    // Lines before the range
    for (NSInteger i = 0; i < startLine - 1; i++) {
        [result addObject:lines[i]];
    }

    // Add the new text (may be multiple lines)
    NSArray *newTextLines = [newText componentsSeparatedByString:@"\n"];
    [result addObjectsFromArray:newTextLines];

    // Lines after the range
    for (NSInteger i = endLine; i < (NSInteger)lines.count; i++) {
        [result addObject:lines[i]];
    }

    self.textEditView.text = [result componentsJoinedByString:@"\n"];
    fileChanged = YES;
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
    [self updateEditButton];
    if (self.isMarkdownFile) {
        if (flag == YES){
            // Entering Edit Mode
            _isPreviewMode = NO;
            self.textEditView.hidden = NO;
            self.markdownView.hidden = YES;
            [textEditView setEditable:true];

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

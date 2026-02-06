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

- (void)markdownView:(UIView *)view didFinishEditingAtStartLine:(NSInteger)startLine
             endLine:(NSInteger)endLine newText:(NSString *)newText {
    NSLog(@"DEBUG FINISH: didFinishEditingAtStartLine called - startLine=%ld, endLine=%ld", (long)startLine, (long)endLine);
    NSLog(@"DEBUG FINISH: newText has %lu lines", (unsigned long)[[newText componentsSeparatedByString:@"\n"] count]);
    [self replaceLines:startLine toLine:endLine withText:newText];
    [_file saveContent:self.textEditView.text];
    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didInsertLineAfterStartLine:(NSInteger)startLine
             endLine:(NSInteger)endLine textBefore:(NSString *)textBefore textAfter:(NSString *)textAfter {
    NSLog(@"DEBUG INSERT: didInsertLineAfterStartLine called - startLine=%ld, endLine=%ld", (long)startLine, (long)endLine);
    NSLog(@"DEBUG INSERT: textBefore='%@', textAfter='%@'", textBefore, textAfter);

    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSLog(@"DEBUG INSERT: Original lines count=%lu", (unsigned long)lines.count);

    NSMutableArray *result = [NSMutableArray array];

    // Lines before the paragraph (lines 0 to startLine-2, which is indices 0 to startLine-2)
    for (NSInteger i = 0; i < startLine - 1; i++) {
        [result addObject:lines[i]];
    }
    NSLog(@"DEBUG INSERT: After adding lines before paragraph, result count=%lu", (unsigned long)result.count);

    // Add the edited content (textBefore may contain multiple lines)
    [result addObjectsFromArray:[textBefore componentsSeparatedByString:@"\n"]];
    NSLog(@"DEBUG INSERT: After adding textBefore, result count=%lu", (unsigned long)result.count);

    // Insert new line(s) with textAfter (textAfter may also contain multiple lines)
    // Splitting by \n handles all cases:
    // - "" splits to [""] (one empty line - cursor was at end)
    // - "\nnice" splits to ["", "nice"] (empty line + content that was after cursor)
    [result addObjectsFromArray:[textAfter componentsSeparatedByString:@"\n"]];
    NSLog(@"DEBUG INSERT: After adding textAfter lines, result count=%lu", (unsigned long)result.count);

    // Lines after the paragraph (starting from endLine, which is index endLine)
    for (NSInteger i = endLine; i < (NSInteger)lines.count; i++) {
        [result addObject:lines[i]];
    }
    NSLog(@"DEBUG INSERT: After adding lines after paragraph, result count=%lu", (unsigned long)result.count);

    self.textEditView.text = [result componentsJoinedByString:@"\n"];
    fileChanged = YES;

    // Debug: show the markdown being saved
    NSArray *debugLines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSLog(@"DEBUG INSERT: Saving markdown with %lu lines", (unsigned long)debugLines.count);
    for (NSInteger i = 18; i <= 28 && i < (NSInteger)debugLines.count; i++) {
        NSLog(@"DEBUG INSERT: Line %ld: '%@' (length: %lu)", (long)(i+1), debugLines[i], (unsigned long)[debugLines[i] length]);
    }

    [_file saveContent:self.textEditView.text];
    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didRequestMergeLineAtStart:(NSInteger)startLine
             endLine:(NSInteger)endLine {
    if (startLine <= 1) return; // Can't merge first paragraph

    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSMutableArray *result = [NSMutableArray array];

    // Find the previous line and merge with the first line of current paragraph
    NSString *prevLine = (startLine >= 2 && startLine - 2 < (NSInteger)lines.count) ? lines[startLine - 2] : @"";
    NSString *currentFirstLine = (startLine >= 1 && startLine - 1 < (NSInteger)lines.count) ? lines[startLine - 1] : @"";
    NSString *merged = [NSString stringWithFormat:@"%@%@", prevLine, currentFirstLine];

    // Lines before the previous line
    for (NSInteger i = 0; i < startLine - 2; i++) {
        [result addObject:lines[i]];
    }

    // Add merged line
    [result addObject:merged];

    // Skip the current first line (merged), add rest of current paragraph if multi-line
    for (NSInteger i = startLine; i < endLine; i++) {
        if (i < (NSInteger)lines.count) {
            [result addObject:lines[i]];
        }
    }

    // Lines after
    for (NSInteger i = endLine; i < (NSInteger)lines.count; i++) {
        [result addObject:lines[i]];
    }

    self.textEditView.text = [result componentsJoinedByString:@"\n"];
    fileChanged = YES;
    [_file saveContent:self.textEditView.text];
    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didInsertTextAtEmptyLine:(NSInteger)lineNumber
             newText:(NSString *)newText {
    NSLog(@"DEBUG EMPTYLINE: didInsertTextAtEmptyLine called - lineNumber=%ld, newText='%@'", (long)lineNumber, newText);

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
    NSLog(@"DEBUG EMPTYLINE: didDeleteEmptyLine called - lineNumber=%ld", (long)lineNumber);

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

    // Stay in edit mode on the same line (which is now the next line after deletion)
    // or previous line if we deleted the last line
    NSInteger nextEditLine = lineNumber;
    if (nextEditLine > (NSInteger)result.count) {
        nextEditLine = result.count; // Focus the last line if we deleted beyond
    }
    if (nextEditLine > 0) {
        // Check if the line at nextEditLine is empty (so we can edit it)
        NSString *lineContent = result[nextEditLine - 1];
        if ([lineContent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
            [self.markdownView setPendingEditingLine:nextEditLine];
        }
    }

    [self renderMarkdownToView];
}

- (void)markdownView:(UIView *)view didSplitEmptyLine:(NSInteger)lineNumber
          textBefore:(NSString *)textBefore textAfter:(NSString *)textAfter {
    NSLog(@"DEBUG EMPTYLINE: didSplitEmptyLine called - lineNumber=%ld, before='%@', after='%@'", (long)lineNumber, textBefore, textAfter);

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
    NSLog(@"DEBUG EMPTYLINE: didMergeEmptyLineWithPrevious called - lineNumber=%ld, text='%@'", (long)lineNumber, text);

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
    // Note: If the merged line has content, it becomes a regular paragraph/element,
    // so we don't set pending editing (that would need different handling)

    [self renderMarkdownToView];
}

#pragma mark - Line Operations

- (void)replaceLines:(NSInteger)startLine toLine:(NSInteger)endLine withText:(NSString *)newText {
    NSLog(@"DEBUG REPLACE: replaceLines called - startLine=%ld, endLine=%ld", (long)startLine, (long)endLine);
    NSLog(@"DEBUG REPLACE: newText='%@'", newText);

    NSArray *lines = [self.textEditView.text componentsSeparatedByString:@"\n"];
    NSLog(@"DEBUG REPLACE: Original lines count=%lu", (unsigned long)lines.count);

    NSMutableArray *result = [NSMutableArray array];

    // Lines before the range
    for (NSInteger i = 0; i < startLine - 1; i++) {
        [result addObject:lines[i]];
    }
    NSLog(@"DEBUG REPLACE: After adding lines before (0 to %ld), result count=%lu", (long)(startLine - 2), (unsigned long)result.count);

    // Add the new text (may be multiple lines)
    NSArray *newTextLines = [newText componentsSeparatedByString:@"\n"];
    NSLog(@"DEBUG REPLACE: newText splits into %lu lines", (unsigned long)newTextLines.count);
    [result addObjectsFromArray:newTextLines];
    NSLog(@"DEBUG REPLACE: After adding newText, result count=%lu", (unsigned long)result.count);

    // Lines after the range
    NSLog(@"DEBUG REPLACE: Adding lines after from index %ld to %lu", (long)endLine, (unsigned long)lines.count - 1);
    for (NSInteger i = endLine; i < (NSInteger)lines.count; i++) {
        [result addObject:lines[i]];
    }
    NSLog(@"DEBUG REPLACE: After adding lines after, result count=%lu", (unsigned long)result.count);

    // Debug: show the result around the area of interest
    for (NSInteger i = 18; i <= 28 && i < (NSInteger)result.count; i++) {
        NSLog(@"DEBUG REPLACE: Result line %ld: '%@'", (long)(i+1), result[i]);
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

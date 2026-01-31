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
#import <libcmark_gfm/cmark-gfm.h>
#import <libcmark_gfm/cmark-gfm-core-extensions.h>
#import <libcmark_gfm/cmark-gfm-extension_api.h>

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
        // Initialize WKWebView with script message handler for checkbox toggling
        WKUserContentController *contentController = [[WKUserContentController alloc] init];
        [contentController addScriptMessageHandler:self name:@"checkboxToggle"];

        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.userContentController = contentController;

        self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
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

// Preprocess markdown to fix nested list parsing for cmark-gfm
// Issues addressed:
// 1. Tabs must be converted to spaces (tabs cause code block detection)
// 2. Use minimal indentation (2 spaces per level) to avoid code block trigger
// 3. Insert blank lines before nested lists for proper block separation
- (NSString *)preprocessMarkdownForNestedLists:(NSString *)markdown {
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    NSMutableArray *processedLines = [NSMutableArray arrayWithCapacity:lines.count * 2];

    NSInteger prevIndentLevel = -1;

    for (NSUInteger idx = 0; idx < lines.count; idx++) {
        NSString *line = lines[idx];

        // Count indent level (tabs or 4-spaces or 2-spaces each count as one level)
        NSUInteger charIndex = 0;
        NSUInteger indentLevel = 0;
        NSUInteger spacesInCurrentLevel = 0;

        while (charIndex < line.length) {
            unichar c = [line characterAtIndex:charIndex];
            if (c == '\t') {
                indentLevel++;
                spacesInCurrentLevel = 0;
                charIndex++;
            } else if (c == ' ') {
                spacesInCurrentLevel++;
                charIndex++;
                // Count 2 or 4 spaces as one indent level
                if (spacesInCurrentLevel >= 2) {
                    if (spacesInCurrentLevel == 2 || spacesInCurrentLevel == 4) {
                        indentLevel++;
                        spacesInCurrentLevel = 0;
                    }
                }
            } else {
                break;
            }
        }

        // Get the content after indentation
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // Check if this line is a list item
        BOOL isListItem = [trimmedLine hasPrefix:@"- "] || [trimmedLine hasPrefix:@"* "] ||
                          [trimmedLine hasPrefix:@"+ "] || [trimmedLine hasPrefix:@"- ["];

        if (isListItem) {
            // If this is a nested list (deeper indent than previous), insert blank line
            if ((NSInteger)indentLevel > prevIndentLevel && prevIndentLevel >= 0) {
                [processedLines addObject:@""];
            }

            prevIndentLevel = indentLevel;

            // Build new line with 2-space indentation per level (avoids code block trigger)
            NSMutableString *newLine = [NSMutableString string];
            for (NSUInteger i = 0; i < indentLevel; i++) {
                [newLine appendString:@"  "]; // 2 spaces per level
            }
            [newLine appendString:trimmedLine];
            [processedLines addObject:newLine];
        } else if (trimmedLine.length == 0) {
            prevIndentLevel = -1;
            [processedLines addObject:line];
        } else {
            // Non-list content: also convert tabs to spaces to be safe
            NSMutableString *newLine = [NSMutableString string];
            for (NSUInteger i = 0; i < indentLevel; i++) {
                [newLine appendString:@"  "];
            }
            [newLine appendString:trimmedLine];
            [processedLines addObject:newLine];
        }
    }

    return [processedLines componentsJoinedByString:@"\n"];
}

- (NSString *)renderMarkdownToHTML:(NSString *)markdown {
    if (!markdown) return nil;

    // Preprocess to fix nested list indentation
    markdown = [self preprocessMarkdownForNestedLists:markdown];

    // Register GFM extensions (tables, strikethrough, tasklist, autolink)
    cmark_gfm_core_extensions_ensure_registered();

    // Create parser with default options
    cmark_parser *parser = cmark_parser_new(CMARK_OPT_DEFAULT);
    if (!parser) return nil;

    // Attach GFM extensions
    cmark_parser_attach_syntax_extension(parser, cmark_find_syntax_extension("table"));
    cmark_parser_attach_syntax_extension(parser, cmark_find_syntax_extension("strikethrough"));
    cmark_parser_attach_syntax_extension(parser, cmark_find_syntax_extension("tasklist"));
    cmark_parser_attach_syntax_extension(parser, cmark_find_syntax_extension("autolink"));

    // Parse the markdown
    const char *utf8String = [markdown UTF8String];
    cmark_parser_feed(parser, utf8String, strlen(utf8String));
    cmark_node *document = cmark_parser_finish(parser);

    if (!document) {
        cmark_parser_free(parser);
        return nil;
    }

    // Get the list of extensions for rendering
    cmark_llist *extensions = cmark_parser_get_syntax_extensions(parser);

    // Render to HTML
    char *html = cmark_render_html(document, CMARK_OPT_DEFAULT, extensions);

    NSString *result = nil;
    if (html) {
        result = [NSString stringWithUTF8String:html];
        free(html);
    }

    cmark_node_free(document);
    cmark_parser_free(parser);

    return result;
}

- (void)renderMarkdownToWebView {
    NSString *markdownContent = self.textEditView.text;
    NSString *htmlString = [self renderMarkdownToHTML:markdownContent];

    if (htmlString) {
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
        NSString *css = [NSString stringWithFormat:@"<style>"
            "body { font-family: -apple-system, ui-sans-serif, sans-serif; line-height: 1.5em; font-weight: 350; font-size: 40px; padding-left: 1em; background-color: %@; color: %@; }"
            "@media (prefers-color-scheme: dark) { body { background-color: %@; color: %@; } } "
            "input[type='checkbox'] { transform: scale(2.4) translateY(0.8em); margin-right: -0.5em; position: absolute; left: 0; top: 0; } "
            "li:has(> input[type='checkbox']) { list-style: none; margin-left: -0.8em; position: relative; padding-left: 1.0em; } "
            "li:has(> input[type='checkbox']:checked) { text-decoration: line-through; opacity: 0.6; } "
            "li:has(> input[type='checkbox']) > p:first-of-type { display: inline; } "
            "li:has(> input[type='checkbox']) > p:first-of-type + ul { margin-top: 0.1em; } "
            "ul:has(input[type='checkbox']) ul { padding-left: 1.25em; } "
            "h1, h2, h3, h4, h5, h6 { margin: 0.5em 0 0 0; padding: 0; } "
            "ul, ol { margin: 0 0 1em 0; padding-left: 2em; } "
            "p { margin: 0.5em 0; } "
            "p + ul, p + ol { margin-top: -0.5em; }"
            "</style>", brightBgColorRGBA, brightTextColorRGBA, darkBgColorRGBA, darkTextColorRGBA];

        // JavaScript to enable checkbox toggling
        NSString *js = @"<script>"
            "document.addEventListener('DOMContentLoaded', function() {"
            "  var checkboxes = document.querySelectorAll('input[type=\"checkbox\"]');"
            "  checkboxes.forEach(function(cb, index) {"
            "    cb.removeAttribute('disabled');"
            "    cb.dataset.index = index;"
            "    cb.addEventListener('change', function(e) {"
            "      webkit.messageHandlers.checkboxToggle.postMessage({"
            "        index: parseInt(this.dataset.index),"
            "        checked: this.checked"
            "      });"
            "    });"
            "  });"
            "});"
            "</script>";

        NSString *finalHtmlString = [NSString stringWithFormat:@"%@%@%@", css, htmlString, js];
        [self.webView loadHTMLString:finalHtmlString baseURL:nil];
    } else {
        [self.webView loadHTMLString:@"<h1>Error rendering markdown</h1>" baseURL:nil];
    }
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"checkboxToggle"]) {
        NSDictionary *body = message.body;
        NSInteger checkboxIndex = [body[@"index"] integerValue];
        BOOL checked = [body[@"checked"] boolValue];

        [self toggleCheckboxAtIndex:checkboxIndex toChecked:checked];
    }
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

        // Save changes
        [_file saveContent:result];
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
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"checkboxToggle"];
}

// Helper to convert UIColor to rgba() string
- (NSString *)rgbaStringFromColor:(UIColor *)color {
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"rgba(%.0f, %.0f, %.0f, %.2f)", r * 255, g * 255, b * 255, a];
}

@end

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
#import "SSWebView.h"
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
        [contentController addScriptMessageHandler:self name:@"lineSelected"];
        [contentController addScriptMessageHandler:self name:@"lineChanged"];
        [contentController addScriptMessageHandler:self name:@"lineEditingDone"];
        [contentController addScriptMessageHandler:self name:@"lineEnterPressed"];
        [contentController addScriptMessageHandler:self name:@"lineBackspaceAtStart"];
        
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.userContentController = contentController;

        self.webView = [[SSWebView alloc] initWithFrame:self.view.bounds configuration:config];
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.webView.navigationDelegate = self;
        [self.view addSubview:self.webView];
        [self.view sendSubviewToBack:self.webView]; // Ensure webView is behind textEditView initially

        // Initial state: Preview mode for markdown files
        _isPreviewMode = YES; 
        self.textEditView.hidden = YES;
        self.webView.hidden = NO;
        [self renderMarkdownToWebView];

        // Setup native format toolbar
        [self setupFormatToolbar];
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

#pragma mark - Format Toolbar

- (void)setupFormatToolbar {
    _formatToolbar = [[UIToolbar alloc] init];
    _formatToolbar.translatesAutoresizingMaskIntoConstraints = NO;

    // Create toolbar items
    UIBarButtonItem *boldButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"bold"]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(formatBold)];

    UIBarButtonItem *italicButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"italic"]
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(formatItalic)];

    UIBarButtonItem *strikeButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"strikethrough"]
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(formatStrikethrough)];

    UIBarButtonItem *flexSpace1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

    UIBarButtonItem *outdentButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"decrease.indent"]
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(formatOutdent)];

    UIBarButtonItem *indentButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"increase.indent"]
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(formatIndent)];

    UIBarButtonItem *flexSpace2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                target:self
                                                                                action:@selector(formatDone)];

    _formatToolbar.items = @[boldButton, italicButton, strikeButton, flexSpace1, outdentButton, indentButton, flexSpace2, doneButton];

    [self.view addSubview:_formatToolbar];

    // Position at bottom, initially hidden
    [NSLayoutConstraint activateConstraints:@[
        [_formatToolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_formatToolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_formatToolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];

    _formatToolbar.hidden = YES;
}

- (void)showFormatToolbar {
    _formatToolbar.hidden = NO;
}

- (void)hideFormatToolbar {
    _formatToolbar.hidden = YES;
}

- (void)formatBold {
    [self.webView evaluateJavaScript:@"applyMarkdownFormat('**', '**')" completionHandler:nil];
}

- (void)formatItalic {
    [self.webView evaluateJavaScript:@"applyMarkdownFormat('*', '*')" completionHandler:nil];
}

- (void)formatStrikethrough {
    [self.webView evaluateJavaScript:@"applyMarkdownFormat('~~', '~~')" completionHandler:nil];
}

- (void)formatIndent {
    [self.webView evaluateJavaScript:@"applyIndent(1)" completionHandler:nil];
}

- (void)formatOutdent {
    [self.webView evaluateJavaScript:@"applyIndent(-1)" completionHandler:nil];
}

- (void)formatDone {
    // Exit editing mode, preserving scroll position
    [self.webView evaluateJavaScript:
        @"var editingEl = document.querySelector('.line.editing');"
        "if (editingEl) {"
        "  webkit.messageHandlers.lineEditingDone.postMessage({line: editingLine, content: editingEl.textContent, direction: 0, scrollY: window.scrollY});"
        "}" completionHandler:nil];
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

        // Count indent level - tabs count as 1 level, 3 spaces = 1 level
        NSUInteger charIndex = 0;
        NSUInteger indentLevel = 0;
        NSUInteger spaceCount = 0;

        while (charIndex < line.length) {
            unichar c = [line characterAtIndex:charIndex];
            if (c == '\t') {
                indentLevel += (spaceCount + 1) / 3;  // Convert accumulated spaces
                spaceCount = 0;
                indentLevel++;
                charIndex++;
            } else if (c == ' ') {
                spaceCount++;
                charIndex++;
            } else {
                break;
            }
        }
        indentLevel += (spaceCount + 1) / 3;  // 2-4 spaces = 1, 5-7 = 2, etc.

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

    return [self renderMarkdownLineToHTML:markdown];
}

// Render a single markdown line without preprocessing (for line-by-line rendering)
// Visual indent is handled separately via CSS margin
- (NSString *)renderMarkdownLineToHTML:(NSString *)markdown {
    if (!markdown) return nil;

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
    [self renderMarkdownToWebViewPreservingScroll:-1];
}

- (void)renderMarkdownToWebViewPreservingScroll:(CGFloat)scrollY {
    NSString *markdownContent = self.textEditView.text;
    NSArray *lines = [markdownContent componentsSeparatedByString:@"\n"];

    // Build HTML with line wrappers
    NSMutableString *htmlBody = [NSMutableString string];

    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        NSString *line = lines[i];

        // Calculate indent level for visual offset (count tabs and spaces)
        NSInteger indentLevel = 0;
        NSUInteger spaceCount = 0;
        for (NSUInteger j = 0; j < line.length; j++) {
            unichar c = [line characterAtIndex:j];
            if (c == '\t') {
                // Each tab is one indent level
                indentLevel++;
                spaceCount = 0;
            } else if (c == ' ') {
                spaceCount++;
                // 3 spaces = 1 indent level (Obsidian compatibility)
                if (spaceCount >= 3) {
                    indentLevel++;
                    spaceCount = 0;
                }
            } else {
                break;
            }
        }
        NSString *indentStyle = indentLevel > 0 ? [NSString stringWithFormat:@" style='margin-left: %ldpx'", (long)(indentLevel * 20)] : @"";

        if (i == _editingLineIndex) {
            // Render as editable markdown with visual indent
            NSString *escapedLine = [self escapeHTMLEntities:line];
            [htmlBody appendFormat:@"<div class='line editing' data-line='%ld'%@ contenteditable='true'>%@</div>", (long)i, indentStyle, escapedLine];
        } else {
            // Render as HTML preview
            if (line.length == 0) {
                // Empty line
                [htmlBody appendFormat:@"<div class='line empty' data-line='%ld'>&nbsp;</div>", (long)i];
            } else {
                // For single-line rendering, strip leading whitespace and render just the content
                // We handle visual indent via CSS margin, so no need to pass indent to cmark
                NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *lineHTML = [self renderMarkdownLineToHTML:trimmedLine];
                // Remove wrapping <p> tags for single lines to avoid extra margins
                if ([lineHTML hasPrefix:@"<p>"] && [lineHTML hasSuffix:@"</p>\n"]) {
                    lineHTML = [lineHTML substringWithRange:NSMakeRange(3, lineHTML.length - 8)];
                }
                [htmlBody appendFormat:@"<div class='line' data-line='%ld'%@>%@</div>", (long)i, indentStyle, lineHTML];
            }
        }
    }

    // Get system colors
    UIColor *bgColor = [UIColor systemBackgroundColor];
    UIColor *textColor = [UIColor labelColor];
    NSString *bgColorRGBA = [self rgbaStringFromColor:bgColor];
    NSString *textColorRGBA = [self rgbaStringFromColor:textColor];

    // CSS
    NSString *css = [NSString stringWithFormat:@"<style>"
        "body { font-family: -apple-system, ui-sans-serif, sans-serif; line-height: 1.5em; font-weight: 350; font-size: 20px; padding-left: 1em; padding-right: 1em; background-color: %@; color: %@; }"
        "@media (prefers-color-scheme: dark) { body { background-color: %@; color: %@; } } "
        ".line { padding: 2px 4px; border-radius: 4px; min-height: 1.5em; } "
        ".line.editing { background-color: rgba(0,122,255,0.1); outline: none; font-family: ui-monospace, monospace; white-space: pre-wrap; } "
        ".line.empty { min-height: 1em; } "
        "input[type='checkbox'] { transform: scale(1.4) translateX(-0.6em) translateY(0.4em); position: absolute; left: 0; top: 0; } "
        "li:has(> input[type='checkbox']) { list-style: none; margin-left: -0.8em; position: relative; padding-left: 1.0em; } "
        "li:has(> input[type='checkbox']:checked) { text-decoration: line-through; opacity: 0.6; } "
        "li:has(> input[type='checkbox']) > p:first-of-type { display: inline; } "
        "li:has(> input[type='checkbox']) > p:first-of-type + ul { margin-top: 0.1em; } "
        "ul:has(input[type='checkbox']) ul { padding-left: 1.25em; } "
        "h1, h2, h3, h4, h5, h6 { margin: 0.3em 0; padding: 0; } "
        "ul, ol { margin: 0; padding-left: 2em; } "
        "p { margin: 0; } "
        "</style>", bgColorRGBA, textColorRGBA, bgColorRGBA, textColorRGBA];

    
    // Full line editing JavaScript
    NSMutableString *jsCode = [NSMutableString stringWithString:@"<script>\n"];
    [jsCode appendFormat:@"var editingLine = %ld;\n", (long)_editingLineIndex];
    [jsCode appendFormat:@"var initialScroll = %f;\n", scrollY];
    [jsCode appendString:@"document.addEventListener('DOMContentLoaded', function() {\n"];
    [jsCode appendString:@"  if (initialScroll >= 0) window.scrollTo(0, initialScroll);\n"];
    [jsCode appendString:@"  var editingEl = document.querySelector('.line.editing');\n"];
    [jsCode appendString:@"  if (editingEl) {\n"];
    [jsCode appendString:@"    editingEl.focus();\n"];
    [jsCode appendString:@"    var range = document.createRange();\n"];
    [jsCode appendString:@"    range.selectNodeContents(editingEl);\n"];
    [jsCode appendString:@"    range.collapse(false);\n"];
    [jsCode appendString:@"    var sel = window.getSelection();\n"];
    [jsCode appendString:@"    sel.removeAllRanges();\n"];
    [jsCode appendString:@"    sel.addRange(range);\n"];
    [jsCode appendString:@"  }\n"];
    // Click handlers for non-editing lines
    [jsCode appendString:@"  document.querySelectorAll('.line:not(.editing)').forEach(function(el) {\n"];
    [jsCode appendString:@"    el.addEventListener('click', function(e) {\n"];
    [jsCode appendString:@"      if (e.target.type === 'checkbox') return;\n"];
    [jsCode appendString:@"      var lineIndex = parseInt(this.dataset.line);\n"];
    [jsCode appendString:@"      webkit.messageHandlers.lineSelected.postMessage({line: lineIndex, scrollY: window.scrollY});\n"];
    [jsCode appendString:@"    });\n"];
    [jsCode appendString:@"  });\n"];
    // Editing line event handlers
    [jsCode appendString:@"  if (editingEl) {\n"];
    [jsCode appendString:@"    editingEl.addEventListener('input', function(e) {\n"];
    [jsCode appendString:@"      webkit.messageHandlers.lineChanged.postMessage({line: editingLine, content: this.textContent});\n"];
    [jsCode appendString:@"    });\n"];
    [jsCode appendString:@"    editingEl.addEventListener('keydown', function(e) {\n"];
    [jsCode appendString:@"      if (e.key === 'Enter' && !e.shiftKey) {\n"];
    [jsCode appendString:@"        e.preventDefault();\n"];
    [jsCode appendString:@"        var sel = window.getSelection();\n"];
    [jsCode appendString:@"        var range = sel.getRangeAt(0);\n"];
    [jsCode appendString:@"        var preRange = document.createRange();\n"];
    [jsCode appendString:@"        preRange.setStart(editingEl, 0);\n"];
    [jsCode appendString:@"        preRange.setEnd(range.startContainer, range.startOffset);\n"];
    [jsCode appendString:@"        var beforeCursor = preRange.toString();\n"];
    [jsCode appendString:@"        var afterCursor = this.textContent.substring(beforeCursor.length);\n"];
    [jsCode appendString:@"        webkit.messageHandlers.lineEnterPressed.postMessage({line: editingLine, beforeCursor: beforeCursor, afterCursor: afterCursor});\n"];
    [jsCode appendString:@"      } else if (e.key === 'ArrowUp') {\n"];
    [jsCode appendString:@"        e.preventDefault();\n"];
    [jsCode appendString:@"        webkit.messageHandlers.lineEditingDone.postMessage({line: editingLine, content: this.textContent, direction: -1, scrollY: window.scrollY});\n"];
    [jsCode appendString:@"      } else if (e.key === 'ArrowDown') {\n"];
    [jsCode appendString:@"        e.preventDefault();\n"];
    [jsCode appendString:@"        webkit.messageHandlers.lineEditingDone.postMessage({line: editingLine, content: this.textContent, direction: 1, scrollY: window.scrollY});\n"];
    [jsCode appendString:@"      } else if (e.key === 'Escape') {\n"];
    [jsCode appendString:@"        e.preventDefault();\n"];
    [jsCode appendString:@"        webkit.messageHandlers.lineEditingDone.postMessage({line: editingLine, content: this.textContent, direction: 0, scrollY: window.scrollY});\n"];
    [jsCode appendString:@"      } else if (e.key === 'Backspace') {\n"];
    [jsCode appendString:@"        var sel = window.getSelection();\n"];
    [jsCode appendString:@"        var range = sel.getRangeAt(0);\n"];
    [jsCode appendString:@"        var preRange = document.createRange();\n"];
    [jsCode appendString:@"        preRange.setStart(editingEl, 0);\n"];
    [jsCode appendString:@"        preRange.setEnd(range.startContainer, range.startOffset);\n"];
    [jsCode appendString:@"        var cursorPos = preRange.toString().length;\n"];
    [jsCode appendString:@"        if (cursorPos === 0 && editingLine > 0) {\n"];
    [jsCode appendString:@"          e.preventDefault();\n"];
    [jsCode appendString:@"          webkit.messageHandlers.lineBackspaceAtStart.postMessage({line: editingLine, content: this.textContent, scrollY: window.scrollY});\n"];
    [jsCode appendString:@"        }\n"];
    [jsCode appendString:@"      }\n"];
    [jsCode appendString:@"    });\n"];
    [jsCode appendString:@"  }\n"];
    // Checkbox toggling
    [jsCode appendString:@"  document.querySelectorAll('input[type=\"checkbox\"]').forEach(function(cb, index) {\n"];
    [jsCode appendString:@"    cb.removeAttribute('disabled');\n"];
    [jsCode appendString:@"    cb.dataset.index = index;\n"];
    [jsCode appendString:@"    cb.addEventListener('change', function(e) {\n"];
    [jsCode appendString:@"      e.stopPropagation();\n"];
    [jsCode appendString:@"      webkit.messageHandlers.checkboxToggle.postMessage({index: parseInt(this.dataset.index), checked: this.checked});\n"];
    [jsCode appendString:@"    });\n"];
    [jsCode appendString:@"  });\n"];
    [jsCode appendString:@"});\n"];
    // Formatting helper functions
    [jsCode appendString:@"function applyMarkdownFormat(prefix, suffix) {\n"];
    [jsCode appendString:@"  var editingEl = document.querySelector('.line.editing');\n"];
    [jsCode appendString:@"  if (!editingEl) return;\n"];
    [jsCode appendString:@"  var sel = window.getSelection();\n"];
    [jsCode appendString:@"  if (sel.rangeCount === 0) return;\n"];
    [jsCode appendString:@"  var range = sel.getRangeAt(0);\n"];
    [jsCode appendString:@"  var selectedText = sel.toString();\n"];
    [jsCode appendString:@"  var newText = prefix + selectedText + suffix;\n"];
    [jsCode appendString:@"  range.deleteContents();\n"];
    [jsCode appendString:@"  range.insertNode(document.createTextNode(newText));\n"];
    [jsCode appendString:@"  sel.removeAllRanges();\n"];
    [jsCode appendString:@"  webkit.messageHandlers.lineChanged.postMessage({line: editingLine, content: editingEl.textContent});\n"];
    [jsCode appendString:@"}\n"];
    [jsCode appendString:@"function applyIndent(direction) {\n"];
    [jsCode appendString:@"  var editingEl = document.querySelector('.line.editing');\n"];
    [jsCode appendString:@"  if (!editingEl) return;\n"];
    [jsCode appendString:@"  var content = editingEl.textContent;\n"];
    [jsCode appendString:@"  if (direction > 0) {\n"];
    [jsCode appendString:@"    editingEl.textContent = '\\t' + content;\n"];  // Tab character
    [jsCode appendString:@"  } else if (direction < 0) {\n"];
    [jsCode appendString:@"    if (content.startsWith('\\t')) {\n"];
    [jsCode appendString:@"      editingEl.textContent = content.substring(1);\n"];
    [jsCode appendString:@"    }\n"];
    [jsCode appendString:@"  }\n"];
    [jsCode appendString:@"  webkit.messageHandlers.lineChanged.postMessage({line: editingLine, content: editingEl.textContent});\n"];
    [jsCode appendString:@"}\n"];
    [jsCode appendString:@"</script>"];

    NSString *finalHtml = [NSString stringWithFormat:@"<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'>%@</head><body>%@%@</body></html>",
                          css, htmlBody, jsCode];

    [self.webView loadHTMLString:finalHtml baseURL:nil];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSLog(@"Received message: %@ with body: %@", message.name, message.body);
    if ([message.name isEqualToString:@"checkboxToggle"]) {
        NSDictionary *body = message.body;
        NSInteger checkboxIndex = [body[@"index"] integerValue];
        BOOL checked = [body[@"checked"] boolValue];
        [self toggleCheckboxAtIndex:checkboxIndex toChecked:checked];
    }
    else if ([message.name isEqualToString:@"lineSelected"]) {
        NSInteger lineIndex = [message.body[@"line"] integerValue];
        CGFloat scrollY = [message.body[@"scrollY"] floatValue];
        [self startEditingLine:lineIndex preserveScroll:scrollY];
    }
    else if ([message.name isEqualToString:@"lineChanged"]) {
        NSInteger lineIndex = [message.body[@"line"] integerValue];
        NSString *newContent = message.body[@"content"];
        [self updateLine:lineIndex withContent:newContent];
    }
    else if ([message.name isEqualToString:@"lineEditingDone"]) {
        NSInteger lineIndex = [message.body[@"line"] integerValue];
        NSString *newContent = message.body[@"content"];
        NSInteger direction = [message.body[@"direction"] integerValue]; // -1=up, 0=blur, 1=down/enter
        CGFloat scrollY = [message.body[@"scrollY"] floatValue];
        [self finishEditingLine:lineIndex withContent:newContent moveDirection:direction preserveScroll:scrollY];
    }
    else if ([message.name isEqualToString:@"lineEnterPressed"]) {
        NSInteger lineIndex = [message.body[@"line"] integerValue];
        NSString *beforeCursor = message.body[@"beforeCursor"];
        NSString *afterCursor = message.body[@"afterCursor"];
        [self insertNewLineAtLine:lineIndex beforeCursor:beforeCursor afterCursor:afterCursor];
    }
    else if ([message.name isEqualToString:@"lineBackspaceAtStart"]) {
        NSInteger lineIndex = [message.body[@"line"] integerValue];
        NSString *currentContent = message.body[@"content"];
        CGFloat scrollY = [message.body[@"scrollY"] floatValue];
        [self mergeLineWithPrevious:lineIndex currentContent:currentContent preserveScroll:scrollY];
    }
}

- (void)startEditingLine:(NSInteger)lineIndex preserveScroll:(CGFloat)scrollY {
    _editingLineIndex = lineIndex;
    [self showFormatToolbar];
    [self renderMarkdownToWebViewPreservingScroll:scrollY];
}

- (void)updateLine:(NSInteger)lineIndex withContent:(NSString *)content {
    NSString *markdown = self.textEditView.text;
    NSMutableArray *lines = [[markdown componentsSeparatedByString:@"\n"] mutableCopy];

    if (lineIndex >= 0 && lineIndex < (NSInteger)lines.count) {
        lines[lineIndex] = content;
        NSString *newMarkdown = [lines componentsJoinedByString:@"\n"];
        self.textEditView.text = newMarkdown;
        fileChanged = YES;
    }
}

- (void)finishEditingLine:(NSInteger)lineIndex withContent:(NSString *)content moveDirection:(NSInteger)direction preserveScroll:(CGFloat)scrollY {
    // Update the line content first
    [self updateLine:lineIndex withContent:content];

    NSString *markdown = self.textEditView.text;
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    NSInteger newLineIndex = -1;

    if (direction == 1) {
        // Enter pressed - move to next line or create new line
        if (lineIndex < (NSInteger)lines.count - 1) {
            newLineIndex = lineIndex + 1;
        } else {
            // At last line - create a new line
            NSMutableArray *mutableLines = [lines mutableCopy];
            [mutableLines addObject:@""];
            self.textEditView.text = [mutableLines componentsJoinedByString:@"\n"];
            newLineIndex = lineIndex + 1;
            fileChanged = YES;
        }
    } else if (direction == -1) {
        // Up arrow - move to previous line
        if (lineIndex > 0) {
            newLineIndex = lineIndex - 1;
        }
    }
    // direction == 0 means blur/tap elsewhere - just exit editing

    _editingLineIndex = newLineIndex;

    // Hide toolbar if no longer editing
    if (newLineIndex < 0) {
        [self hideFormatToolbar];
    }

    // Save and re-render, preserving scroll position
    [_file saveContent:self.textEditView.text];
    [self renderMarkdownToWebViewPreservingScroll:scrollY];
}

- (void)insertNewLineAtLine:(NSInteger)lineIndex beforeCursor:(NSString *)beforeCursor afterCursor:(NSString *)afterCursor {
    NSString *markdown = self.textEditView.text;
    NSMutableArray *lines = [[markdown componentsSeparatedByString:@"\n"] mutableCopy];

    if (lineIndex >= 0 && lineIndex < (NSInteger)lines.count) {
        // Replace current line with text before cursor
        lines[lineIndex] = beforeCursor;
        // Insert new line with text after cursor
        [lines insertObject:afterCursor atIndex:lineIndex + 1];

        NSString *newMarkdown = [lines componentsJoinedByString:@"\n"];
        self.textEditView.text = newMarkdown;
        fileChanged = YES;

        // Start editing the new line
        _editingLineIndex = lineIndex + 1;

        // Save and re-render
        [_file saveContent:newMarkdown];
        [self renderMarkdownToWebView];
    }
}

- (void)mergeLineWithPrevious:(NSInteger)lineIndex currentContent:(NSString *)currentContent preserveScroll:(CGFloat)scrollY {
    if (lineIndex <= 0) return; // Can't merge first line with previous

    NSString *markdown = self.textEditView.text;
    NSMutableArray *lines = [[markdown componentsSeparatedByString:@"\n"] mutableCopy];

    if (lineIndex < (NSInteger)lines.count) {
        // Get previous line content
        NSString *previousContent = lines[lineIndex - 1];

        // Merge: previous line + current line content
        NSString *mergedContent = [previousContent stringByAppendingString:currentContent];

        // Update previous line with merged content
        lines[lineIndex - 1] = mergedContent;

        // Remove current line
        [lines removeObjectAtIndex:lineIndex];

        NSString *newMarkdown = [lines componentsJoinedByString:@"\n"];
        self.textEditView.text = newMarkdown;
        fileChanged = YES;

        // Start editing the previous line (cursor will be at end due to default behavior)
        _editingLineIndex = lineIndex - 1;

        // Save and re-render
        [_file saveContent:newMarkdown];
        [self renderMarkdownToWebViewPreservingScroll:scrollY];
    }
}

- (NSString *)escapeHTMLEntities:(NSString *)text {
    NSMutableString *escaped = [text mutableCopy];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"'" withString:@"&#39;" options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
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
    _editingLineIndex = -1;
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
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"lineSelected"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"lineChanged"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"lineEditingDone"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"lineEnterPressed"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"lineBackspaceAtStart"];
}

// Helper to convert UIColor to rgba() string
- (NSString *)rgbaStringFromColor:(UIColor *)color {
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"rgba(%.0f, %.0f, %.0f, %.2f)", r * 255, g * 255, b * 255, a];
}

@end

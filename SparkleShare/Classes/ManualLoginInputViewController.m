//
//  ManualLoginInputViewController.m
//  SparkleShare
//
//  Created by Sergey Klimov on 11.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "ManualLoginInputViewController.h"

@interface ManualLoginInputViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *urlLabel;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *instructionLabel;
@end

@implementation ManualLoginInputViewController
@synthesize urlField, codeField;

- (id)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = @"Manual Login";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    [self setupScrollView];
    [self setupUI];
    [self setupConstraints];

    // Keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupScrollView {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];
}

- (void)setupUI {
    // Instruction label
    self.instructionLabel = [[UILabel alloc] init];
    self.instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.instructionLabel.text = @"Enter your SparkleShare server details to connect this device.";
    self.instructionLabel.textColor = [UIColor secondaryLabelColor];
    self.instructionLabel.font = [UIFont systemFontOfSize:15];
    self.instructionLabel.numberOfLines = 0;
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.instructionLabel];

    // URL section
    self.urlLabel = [[UILabel alloc] init];
    self.urlLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.urlLabel.text = @"SERVER URL";
    self.urlLabel.textColor = [UIColor secondaryLabelColor];
    self.urlLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.contentView addSubview:self.urlLabel];

    self.urlField = [[UITextField alloc] init];
    self.urlField.translatesAutoresizingMaskIntoConstraints = NO;
    self.urlField.placeholder = @"https://your-server.com/link";
    self.urlField.borderStyle = UITextBorderStyleNone;
    self.urlField.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.urlField.layer.cornerRadius = 10;
    self.urlField.font = [UIFont systemFontOfSize:17];
    self.urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.urlField.returnKeyType = UIReturnKeyNext;
    self.urlField.delegate = self;
    self.urlField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // Add padding to text field
    UIView *urlPaddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 0)];
    self.urlField.leftView = urlPaddingView;
    self.urlField.leftViewMode = UITextFieldViewModeAlways;
    [self.contentView addSubview:self.urlField];

    // Code section
    self.codeLabel = [[UILabel alloc] init];
    self.codeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.codeLabel.text = @"LINK CODE";
    self.codeLabel.textColor = [UIColor secondaryLabelColor];
    self.codeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.contentView addSubview:self.codeLabel];

    self.codeField = [[UITextField alloc] init];
    self.codeField.translatesAutoresizingMaskIntoConstraints = NO;
    self.codeField.placeholder = @"Enter link code";
    self.codeField.borderStyle = UITextBorderStyleNone;
    self.codeField.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.codeField.layer.cornerRadius = 10;
    self.codeField.font = [UIFont systemFontOfSize:17];
    self.codeField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.codeField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.codeField.returnKeyType = UIReturnKeyDone;
    self.codeField.delegate = self;
    self.codeField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // Add padding to text field
    UIView *codePaddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 0)];
    self.codeField.leftView = codePaddingView;
    self.codeField.leftViewMode = UITextFieldViewModeAlways;
    [self.contentView addSubview:self.codeField];
}

- (void)setupConstraints {
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        // Scroll view
        [self.scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        // Content view
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],

        // Instruction label
        [self.instructionLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:24],
        [self.instructionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.instructionLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        // URL label
        [self.urlLabel.topAnchor constraintEqualToAnchor:self.instructionLabel.bottomAnchor constant:32],
        [self.urlLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.urlLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        // URL field
        [self.urlField.topAnchor constraintEqualToAnchor:self.urlLabel.bottomAnchor constant:8],
        [self.urlField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.urlField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.urlField.heightAnchor constraintEqualToConstant:50],

        // Code label
        [self.codeLabel.topAnchor constraintEqualToAnchor:self.urlField.bottomAnchor constant:24],
        [self.codeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.codeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        // Code field
        [self.codeField.topAnchor constraintEqualToAnchor:self.codeLabel.bottomAnchor constant:8],
        [self.codeField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.codeField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.codeField.heightAnchor constraintEqualToConstant:50],

        // Content view bottom
        [self.contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:self.codeField.bottomAnchor constant:40],
    ]];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.urlField) {
        [self.codeField becomeFirstResponder];
    } else if (textField == self.codeField) {
        [self.codeField resignFirstResponder];
        [self editDone:nil];
    }
    return YES;
}

#pragma mark - Keyboard handling

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0, 0, keyboardFrame.size.height, 0);

    [UIView animateWithDuration:duration animations:^{
        self.scrollView.contentInset = contentInsets;
        self.scrollView.scrollIndicatorInsets = contentInsets;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    CGFloat duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    [UIView animateWithDuration:duration animations:^{
        self.scrollView.contentInset = UIEdgeInsetsZero;
        self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    }];
}

#pragma mark - Actions

- (void)editDone:(id)sender {
    [self.delegate loginInputViewController:self willSetLink:[NSURL URLWithString:self.urlField.text] code:self.codeField.text];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

@end

//
//  SelectLoginInputViewController.m
//  SparkleShare
//
//  Created by Sergey Klimov on 11.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "SelectLoginInputViewController.h"
#import "QRCodeLoginInputViewController.h"
#import "ManualLoginInputViewController.h"
#import "UIColor+ApplicationColors.h"
#import "UIViewController+AutoPlatformNibName.h"
@interface SelectLoginInputViewController ()
@property (strong, nonatomic) QRCodeLoginInputViewController *qrcodeLoginInputController;
@property (strong, nonatomic) ManualLoginInputViewController *manualLoginInputViewController;

@end

@implementation SelectLoginInputViewController
@synthesize qrcodeLoginInputController, manualLoginInputViewController;

- (id)init {
    if (self = [self initWithAutoPlatformNibName]) {
    }
    return self;
}

- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
	[super didReceiveMemoryWarning];

	// Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view from its nib.
}

- (void)viewDidUnload {
	[super viewDidUnload];
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
}

- (void) viewWillAppear: (BOOL) animated {
	[self.navigationController setNavigationBarHidden: YES animated: NO];
	self.navigationController.navigationBar.tintColor = [UIColor navBarColor];

	[super viewWillAppear: animated];
}

- (void) viewWillDisappear: (BOOL) animated {
	[self.navigationController setNavigationBarHidden: NO animated: animated];
	[super viewWillDisappear: animated];
}


- (BOOL)shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation) interfaceOrientation {
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}


- (void)loginInputViewController: (LoginInputViewController *) loginInputViewController
       willSetLink: (NSURL *) link code: (NSString *) code {
	[self.navigationController popViewControllerAnimated:NO];
	[self.delegate loginInputViewController: loginInputViewController willSetLink: link code: code];
}

- (IBAction)openQRCodeView: (id) sender {
	if (self.qrcodeLoginInputController == nil) {
		self.qrcodeLoginInputController = [[QRCodeLoginInputViewController alloc] init];
		self.qrcodeLoginInputController.delegate = self;
	}
	[self.navigationController pushViewController: self.qrcodeLoginInputController animated: YES];
}

- (IBAction)openManualView: (id) sender {
	if (self.manualLoginInputViewController == nil) {
		self.manualLoginInputViewController = [[ManualLoginInputViewController alloc] init];
		self.manualLoginInputViewController.delegate = self;
	}
	[self.navigationController pushViewController: self.manualLoginInputViewController animated: YES];
}

@end

//
//  QRCodeLoginInputViewController.m
//  SparkleShare
//
//  Created by Sergey Klimov on 11.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "QRCodeLoginInputViewController.h"
#import "ZBarSDK/ZBarSDK.h"

@interface QRCodeLoginInputViewController ()
@end


@implementation QRCodeLoginInputViewController
@synthesize readerView, urlLabel, codeLabel;

- (id)init {
	self = [super init];
	if (self) {
		[ZBarReaderView class];
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
	// the delegate receives decode results
	readerView.readerDelegate = self;
	qrCaptured = NO;
    
    //disable auto flash
    readerView.torchMode = 0;
    
	// support the simulator
	if (TARGET_IPHONE_SIMULATOR) {
		cameraSim = [[ZBarCameraSimulator alloc]
		             initWithViewController: self];
		cameraSim.readerView = readerView;
	}
}

- (void)viewDidAppear: (BOOL) animated {
	[readerView start];
}

- (void)viewWillDisappear: (BOOL) animated {
	[readerView stop];
}

- (void) readerView: (ZBarReaderView *) view
       didReadSymbols: (ZBarSymbolSet *) syms
       fromImage: (UIImage *) img {
	NSString *result;
	NSString *prefix = @"SSHARE:";
	// do something useful with results
	for (ZBarSymbol *sym in syms) {
		result = sym.data;
		break;
	}

	if ([result hasPrefix: prefix]) {
		NSArray *chunks = [[result substringFromIndex: [prefix length]] componentsSeparatedByString: @"#"];
		if ([chunks count] == 2) {
			self.urlLabel.text = [chunks objectAtIndex: 0];
			self.codeLabel.text = [chunks objectAtIndex: 1];
			qrCaptured = YES;
            
            [self editDone:self];
		}
	}
}

- (void) editDone: (id) sender {
	if (qrCaptured)
		[self.delegate loginInputViewController: self willSetLink: [NSURL URLWithString: self.urlLabel.text] code: self.codeLabel.text];
	else
		[self.navigationController popViewControllerAnimated: YES];
}

@end

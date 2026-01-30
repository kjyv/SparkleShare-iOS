//
//  QRCodeLoginInputViewController.h
//  SparkleShare
//
//  Created by Sergey Klimov on 11.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "LoginInputViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface QRCodeLoginInputViewController : LoginInputViewController <AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *urlLabel;

@end

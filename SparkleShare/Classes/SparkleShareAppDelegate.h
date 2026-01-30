//
//  SparkleShareAppDelegate.h
//  SparkleShare
//
//  Created by Sergey Klimov on 07.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "LoginInputViewController.h"
#import "SSConnection.h"

@class SelectLoginInputViewController;

@interface SparkleShareAppDelegate : UIResponder <UIApplicationDelegate, LoginInputViewControllerDelegate, SSConnectionDelegate>
{
	SSConnection *connection;
}
@property (strong, nonatomic) UIWindow *window;

@property (strong, nonatomic) UINavigationController *navigationController;
@property (strong, nonatomic) SelectLoginInputViewController *loginInputViewController;
@property (strong, nonatomic, readonly) SSConnection *connection;
//
//@property (strong, nonatomic) UISplitViewController *splitViewController;

@end

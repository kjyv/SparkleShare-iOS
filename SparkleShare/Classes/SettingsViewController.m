//
//  SettingsViewController.m
//  SparkleShare
//

#import "SettingsViewController.h"

typedef NS_ENUM(NSInteger, SettingsSection) {
    SettingsSectionDevice = 0,
    SettingsSectionConnection,
    SettingsSectionAbout,
    SettingsSectionCount
};

typedef NS_ENUM(NSInteger, DeviceRow) {
    DeviceRowName = 0,
    DeviceRowCount
};

typedef NS_ENUM(NSInteger, ConnectionRow) {
    ConnectionRowAllowSelfSigned = 0,
    ConnectionRowLogout,
    ConnectionRowCount
};

typedef NS_ENUM(NSInteger, AboutRow) {
    AboutRowVersion = 0,
    AboutRowCount
};

@interface SettingsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UISwitch *selfSignedSwitch;
@property (nonatomic, strong) UITextField *deviceNameField;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self
                                                                                           action:@selector(donePressed)];

    // Dismiss keyboard on tap
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:tap];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)donePressed {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SettingsSectionDevice:
            return DeviceRowCount;
        case SettingsSectionConnection:
            return ConnectionRowCount;
        case SettingsSectionAbout:
            return AboutRowCount;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SettingsSectionDevice:
            return @"Device";
        case SettingsSectionConnection:
            return @"Connection";
        case SettingsSectionAbout:
            return @"About";
        default:
            return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == SettingsSectionDevice) {
        return @"Custom name for this device shown on the server. Only takes effect on next login.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];

    if (indexPath.section == SettingsSectionDevice) {
        if (indexPath.row == DeviceRowName) {
            cell.textLabel.text = @"Device Name";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            self.deviceNameField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 180, 30)];
            self.deviceNameField.textAlignment = NSTextAlignmentRight;
            self.deviceNameField.placeholder = [[UIDevice currentDevice] name];
            self.deviceNameField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"customDeviceName"];
            self.deviceNameField.delegate = self;
            self.deviceNameField.returnKeyType = UIReturnKeyDone;
            self.deviceNameField.autocorrectionType = UITextAutocorrectionTypeNo;
            self.deviceNameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            cell.accessoryView = self.deviceNameField;
        }
    } else if (indexPath.section == SettingsSectionConnection) {
        if (indexPath.row == ConnectionRowAllowSelfSigned) {
            cell.textLabel.text = @"Allow Self-Signed Certificates";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            self.selfSignedSwitch = [[UISwitch alloc] init];
            self.selfSignedSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"allowSelfSignedCertificates"];
            [self.selfSignedSwitch addTarget:self action:@selector(selfSignedSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = self.selfSignedSwitch;
        } else if (indexPath.row == ConnectionRowLogout) {
            cell.textLabel.text = @"Logout";
            cell.textLabel.textColor = [UIColor systemRedColor];
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    } else if (indexPath.section == SettingsSectionAbout) {
        if (indexPath.row == AboutRowVersion) {
            cell.textLabel.text = @"Version";
            NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)", version, build];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SettingsSectionConnection && indexPath.row == ConnectionRowLogout) {
        [self confirmLogout];
    }
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.deviceNameField) {
        NSString *name = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length > 0) {
            [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"customDeviceName"];
        } else {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"customDeviceName"];
        }
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Actions

- (void)selfSignedSwitchChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"allowSelfSignedCertificates"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)confirmLogout {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Logout"
                                                                   message:@"Are you sure you want to logout? You will need to link your device again."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Logout" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self performLogout];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performLogout {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

    // Clear credentials
    [userDefaults removeObjectForKey:@"link"];
    [userDefaults removeObjectForKey:@"authCode"];
    [userDefaults removeObjectForKey:@"identCode"];
    [userDefaults setBool:NO forKey:@"linked"];
    [userDefaults synchronize];

    // Dismiss settings and restart app to login screen
    [self dismissViewControllerAnimated:YES completion:^{
        // Post notification to trigger re-authentication
        dispatch_async(dispatch_get_main_queue(), ^{
            // Restart the connection process which will show login screen
            UIApplication *app = [UIApplication sharedApplication];
            id<UIApplicationDelegate> delegate = app.delegate;

            // Re-initialize connection which will fail and show login
            if ([delegate respondsToSelector:@selector(application:didFinishLaunchingWithOptions:)]) {
                [delegate application:app didFinishLaunchingWithOptions:nil];
            }
        });
    }];
}

@end

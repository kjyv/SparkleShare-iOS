//
//  QRCodeLoginInputViewController.m
//  SparkleShare
//
//  Created by Sergey Klimov on 11.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "QRCodeLoginInputViewController.h"

@interface QRCodeLoginInputViewController ()
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) UIView *previewContainer;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) UILabel *instructionLabel;
@property (nonatomic, strong) UIView *scanFrame;
@property (nonatomic, assign) BOOL qrCaptured;
@end

@implementation QRCodeLoginInputViewController
@synthesize urlLabel, codeLabel;

- (id)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = @"Scan QR Code";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor blackColor];
    self.qrCaptured = NO;

    [self setupUI];
    [self setupCamera];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.captureSession && !self.captureSession.isRunning) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.captureSession startRunning];
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (self.captureSession && self.captureSession.isRunning) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.captureSession stopRunning];
        });
    }
}

- (void)setupUI {
    // Preview container
    self.previewContainer = [[UIView alloc] init];
    self.previewContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewContainer.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.previewContainer];

    // Overlay view for dimming
    self.overlayView = [[UIView alloc] init];
    self.overlayView.translatesAutoresizingMaskIntoConstraints = NO;
    self.overlayView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.overlayView];

    // Instruction label
    self.instructionLabel = [[UILabel alloc] init];
    self.instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.instructionLabel.text = @"Point your camera at a SparkleShare QR code";
    self.instructionLabel.textColor = [UIColor whiteColor];
    self.instructionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionLabel.numberOfLines = 0;
    [self.view addSubview:self.instructionLabel];

    // Scan frame (visual indicator)
    self.scanFrame = [[UIView alloc] init];
    self.scanFrame.translatesAutoresizingMaskIntoConstraints = NO;
    self.scanFrame.backgroundColor = [UIColor clearColor];
    self.scanFrame.layer.borderColor = [UIColor whiteColor].CGColor;
    self.scanFrame.layer.borderWidth = 3.0;
    self.scanFrame.layer.cornerRadius = 12;
    [self.view addSubview:self.scanFrame];

    // Hidden labels for storing scanned data
    self.urlLabel = [[UILabel alloc] init];
    self.urlLabel.hidden = YES;
    [self.view addSubview:self.urlLabel];

    self.codeLabel = [[UILabel alloc] init];
    self.codeLabel.hidden = YES;
    [self.view addSubview:self.codeLabel];

    // Constraints
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        // Preview container fills the view
        [self.previewContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.previewContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.previewContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.previewContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        // Overlay
        [self.overlayView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.overlayView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.overlayView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.overlayView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        // Instruction label at the top
        [self.instructionLabel.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:20],
        [self.instructionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.instructionLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Scan frame in the center
        [self.scanFrame.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.scanFrame.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
        [self.scanFrame.widthAnchor constraintEqualToConstant:250],
        [self.scanFrame.heightAnchor constraintEqualToConstant:250],
    ]];
}

- (void)setupCamera {
    // Check camera authorization
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

    if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self initializeCamera];
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showCameraAccessDeniedAlert];
                });
            }
        }];
    } else if (status == AVAuthorizationStatusAuthorized) {
        [self initializeCamera];
    } else {
        [self showCameraAccessDeniedAlert];
    }
}

- (void)initializeCamera {
    self.captureSession = [[AVCaptureSession alloc] init];

    // Get the back camera
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device) {
        [self showNoCameraAlert];
        return;
    }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (error || !input) {
        [self showCameraErrorAlert:error];
        return;
    }

    if ([self.captureSession canAddInput:input]) {
        [self.captureSession addInput:input];
    }

    // Metadata output for QR codes
    AVCaptureMetadataOutput *metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    if ([self.captureSession canAddOutput:metadataOutput]) {
        [self.captureSession addOutput:metadataOutput];
        [metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        metadataOutput.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
    }

    // Preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.previewContainer.bounds;
    [self.previewContainer.layer addSublayer:self.previewLayer];

    // Start running
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.captureSession startRunning];
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.previewContainer.bounds;
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection {

    if (self.qrCaptured) {
        return;
    }

    for (AVMetadataObject *metadata in metadataObjects) {
        if ([metadata isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            AVMetadataMachineReadableCodeObject *qrCode = (AVMetadataMachineReadableCodeObject *)metadata;
            NSString *result = qrCode.stringValue;

            if (result) {
                [self processQRCode:result];
                break;
            }
        }
    }
}

- (void)processQRCode:(NSString *)result {
    NSString *prefix = @"SSHARE:";

    if ([result hasPrefix:prefix]) {
        NSArray *chunks = [[result substringFromIndex:[prefix length]] componentsSeparatedByString:@"#"];
        if ([chunks count] == 2) {
            self.qrCaptured = YES;

            // Stop scanning
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self.captureSession stopRunning];
            });

            self.urlLabel.text = [chunks objectAtIndex:0];
            self.codeLabel.text = [chunks objectAtIndex:1];

            // Visual feedback
            [self showSuccessFeedback];

            // Proceed after short delay for user feedback
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self editDone:self];
            });
        }
    }
}

- (void)showSuccessFeedback {
    // Flash the scan frame green
    self.scanFrame.layer.borderColor = [UIColor systemGreenColor].CGColor;
    self.scanFrame.layer.borderWidth = 5.0;

    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
}

#pragma mark - Alerts

- (void)showCameraAccessDeniedAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Camera Access Required"
                                                                   message:@"Please enable camera access in Settings to scan QR codes."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showNoCameraAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Camera"
                                                                   message:@"This device does not have a camera."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showCameraErrorAlert:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Camera Error"
                                                                   message:error.localizedDescription ?: @"Could not initialize camera."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)editDone:(id)sender {
    if (self.qrCaptured) {
        [self.delegate loginInputViewController:self willSetLink:[NSURL URLWithString:self.urlLabel.text] code:self.codeLabel.text];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end

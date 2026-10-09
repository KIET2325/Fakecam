#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface WincareFakeCamManager : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
+ (instancetype)sharedInstance;
@property (nonatomic, strong) UIImage *selectedImage;
@property (nonatomic, strong) UIImageView *previewOverlayView; 
@property (nonatomic, assign) BOOL isPickerOpen;
- (void)showPhotoPicker;
- (CMSampleBufferRef)createFakeBuffer;
- (void)triggerCaptureButtonIfNeeded;
@end

@implementation WincareFakeCamManager

+ (instancetype)sharedInstance {
    static WincareFakeCamManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WincareFakeCamManager alloc] init];
        shared.isPickerOpen = NO;
    });
    return shared;
}

- (UIViewController *)topViewControllerWithRootVC:(UIViewController *)rootVC {
    if ([rootVC isKindOfClass:[UITabBarController class]]) {
        return [self topViewControllerWithRootVC:((UITabBarController *)rootVC).selectedViewController];
    }
    if ([rootVC isKindOfClass:[UINavigationController class]]) {
        return [self topViewControllerWithRootVC:((UINavigationController *)rootVC).visibleViewController];
    }
    if (rootVC.presentedViewController) {
        return [self topViewControllerWithRootVC:rootVC.presentedViewController];
    }
    return rootVC;
}

- (void)showPhotoPicker {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isPickerOpen) return;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.isPickerOpen) return;
            
            UIWindow *keyWindow = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                            if (window.isKeyWindow) { keyWindow = window; break; }
                        }
                    }
                    if (keyWindow) break;
                }
            }
            if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
            
            UIViewController *topVC = [self topViewControllerWithRootVC:keyWindow.rootViewController];
            if (!topVC) return;
            
            self.isPickerOpen = YES;
            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.delegate = self;
            picker.modalPresentationStyle = UIModalPresentationFullScreen;
            
            [topVC presentViewController:picker animated:YES completion:nil];
        });
    });
}

- (void)triggerCaptureButtonIfNeeded {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                        if (window.isKeyWindow) { keyWindow = window; break; }
                    }
                }
            }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
        
        [self findAndClickButtonInView:keyWindow];
    });
}

- (BOOL)findAndClickButtonInView:(UIView *)view {
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        if (btn.userInteractionEnabled && !btn.hidden && btn.alpha > 0.1) {
            [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
            return YES;
        }
    }
    
    for (UIView *subview in view.subviews) {
        if ([self findAndClickButtonInView:subview]) {
            return YES;
        }
    }
    return NO;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    if (img) {
        if (img.imageOrientation != UIImageOrientationUp) {
            UIGraphicsBeginImageContextWithOptions(img.size, NO, img.scale);
            [img drawInRect:CGRectMake(0, 0, img.size.width, img.size.height)];
            img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
        
        self.selectedImage = img;
        
        if (self.previewOverlayView) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.previewOverlayView.image = img;
                self.previewOverlayView.backgroundColor = [UIColor blackColor];
                self.previewOverlayView.hidden = NO;
            });
        }
    }
    
    [picker dismissViewControllerAnimated:YES completion:^{
        self.isPickerOpen = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self triggerCaptureButtonIfNeeded];
        });
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        self.isPickerOpen = NO;
    }];
}

- (CMSampleBufferRef)createFakeBuffer {
    if (!self.selectedImage) return NULL;
    
    CGImageRef imgRef = self.selectedImage.CGImage;
    size_t w = CGImageGetWidth(imgRef);
    size_t h = CGImageGetHeight(imgRef);
    
    NSDictionary *opts = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    
    CVPixelBufferRef pxBuf = NULL;
    CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)opts, &pxBuf);
    
    CVPixelBufferLockBaseAddress(pxBuf, 0);
    void *data = CVPixelBufferGetBaseAddress(pxBuf);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef ctx = CGBitmapContextCreate(data, w, h, 8, CVPixelBufferGetBytesPerRow(pxBuf), cs, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), imgRef);
    CGColorSpaceRelease(cs);
    CGContextRelease(ctx);
    CVPixelBufferUnlockBaseAddress(pxBuf, 0);
    
    CMVideoFormatDescriptionRef vInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pxBuf, &vInfo);
    
    CMSampleTimingInfo tInfo = kCMTimingInfoInvalid;
    CMSampleBufferRef sBuf = NULL;
    
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pxBuf, YES, NULL, NULL, vInfo, &tInfo, &sBuf);
    
    CVPixelBufferRelease(pxBuf);
    CFRelease(vInfo);
    return sBuf;
}
@end

// ==================== HOOK PREVIEW CAMERA ====================

%hook AVCaptureVideoPreviewLayer
- (void)setSession:(AVCaptureSession *)session {
    %orig;
    if (!session) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL isScanningQR = NO;
        for (AVCaptureOutput *output in session.outputs) {
            if ([output isKindOfClass:[AVCaptureMetadataOutput class]]) {
                isScanningQR = YES;
                break;
            }
        }

        if (isScanningQR) {
            if ([WincareFakeCamManager sharedInstance].previewOverlayView) {
                [WincareFakeCamManager sharedInstance].previewOverlayView.hidden = YES;
            }
            return; 
        }

        UIView *pView = nil;
        if ([self respondsToSelector:@selector(delegate)] && [((id)self.delegate) isKindOfClass:[UIView class]]) {
            pView = (UIView *)self.delegate;
        }
        
        if (![WincareFakeCamManager sharedInstance].previewOverlayView) {
            UIImageView *fakeView = [[UIImageView alloc] initWithFrame:self.bounds];
            fakeView.contentMode = UIViewContentModeScaleAspectFit; 
            fakeView.backgroundColor = [UIColor blackColor]; 
            fakeView.clipsToBounds = YES;
            fakeView.hidden = YES;
            
            if (pView) {
                [pView addSubview:fakeView];
                [pView bringSubviewToFront:fakeView];
            } else {
                [self addSublayer:fakeView.layer];
            }
            [WincareFakeCamManager sharedInstance].previewOverlayView = fakeView;
        }
        
        if ([WincareFakeCamManager sharedInstance].selectedImage) {
            [WincareFakeCamManager sharedInstance].previewOverlayView.image = [WincareFakeCamManager sharedInstance].selectedImage;
            [WincareFakeCamManager sharedInstance].previewOverlayView.hidden = NO;
        }
        
        [[WincareFakeCamManager sharedInstance] showPhotoPicker];
    });
}

- (void)setBounds:(CGRect)bounds {
    %orig;
    if ([WincareFakeCamManager sharedInstance].previewOverlayView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [WincareFakeCamManager sharedInstance].previewOverlayView.frame = bounds;
        });
    }
}
%end

// ==================== HOOK DATA OUTPUT ====================

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)del queue:(dispatch_queue_t)q {
    if (del) {
        Class delClass = [del class];
        SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
        
        if ([del respondsToSelector:sel]) {
            static dispatch_once_t token;
            dispatch_once(&token, ^{
                Method m = class_getInstanceMethod(delClass, sel);
                IMP origImp = method_getImplementation(m);
                
                typedef void (*OrigFunc)(id, SEL, id, CMSampleBufferRef, id);
                OrigFunc orig = (OrigFunc)origImp;
                
                id block = ^(id slf, id out, CMSampleBufferRef sBuf, id conn) {
                    CMSampleBufferRef fake = [[WincareFakeCamManager sharedInstance] createFakeBuffer];
                    if (fake) {
                        orig(slf, sel, out, fake, conn);
                        CFRelease(fake);
                    } else {
                        orig(slf, sel, out, sBuf, conn);
                    }
                };
                IMP newImp = imp_implementationWithBlock(block);
                class_replaceMethod(delClass, sel, newImp, method_getTypeEncoding(m));
            });
        }
    }
    %orig(del, q);
}
%end

// ==================== HOOK CHỤP ẢNH TĨNH ====================

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *fake = [WincareFakeCamManager sharedInstance].selectedImage;
    if (fake) return UIImageJPEGRepresentation(fake, 0.9);
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    UIImage *fake = [WincareFakeCamManager sharedInstance].selectedImage;
    if (fake) return fake.CGImage;
    return %orig;
}
%end

%hook AVCaptureStillImageOutput
- (void)captureStillImageAsynchronouslyFromConnection:(id)conn completionHandler:(void (^)(CMSampleBufferRef, NSError *))h {
    if (!h) { %orig; return; }
    
    void (^customH)(CMSampleBufferRef, NSError *) = ^(CMSampleBufferRef sBuf, NSError *err) {
        CMSampleBufferRef fake = [[WincareFakeCamManager sharedInstance] createFakeBuffer];
        if (fake) {
            h(fake, err);
            CFRelease(fake);
        } else {
            h(sBuf, err);
        }
    };
    %orig(conn, customH);
}
}
%end

#pragma clang diagnostic pop

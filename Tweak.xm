#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface WincareFakeCamManager : NSObject 
    <UIImagePickerControllerDelegate, 
     UINavigationControllerDelegate>
+ (instancetype)sharedInstance;
@property (nonatomic, strong) UIImage *selectedImage;
@property (nonatomic, strong) UIImageView *previewOverlayView; 
@property (nonatomic, assign) BOOL isPickerOpen;
@property (nonatomic, assign) BOOL isCaptureMode;
@property (nonatomic, assign) CMTime lastPts;
- (void)showPhotoPicker;
- (CMSampleBufferRef)createFakeBuffer;
- (void)detectCaptureModeByUI;
@end

@implementation WincareFakeCamManager

+ (instancetype)sharedInstance {
    static WincareFakeCamManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WincareFakeCamManager alloc] init];
        shared.isPickerOpen = NO;
        shared.isCaptureMode = NO;
        shared.lastPts = kCMTimeZero;
    });
    return shared;
}

- (UIViewController *)topViewControllerWithRootVC:(UIViewController *)rootVC {
    if ([rootVC isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tab = (UITabBarController *)rootVC;
        return [self topViewControllerWithRootVC:tab.selectedViewController];
    }
    if ([rootVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)rootVC;
        return [self topViewControllerWithRootVC:nav.visibleViewController];
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
                    if (scene.activationState == UISceneActivationStateForegroundActive && 
                        [scene isKindOfClass:[UIWindowScene class]]) {
                        UIWindowScene *ws = (UIWindowScene *)scene;
                        for (UIWindow *window in ws.windows) {
                            if (window.isKeyWindow) {
                                keyWindow = window;
                                break;
                            }
                        }
                    }
                    if (keyWindow) break;
                }
            }
            
            if (!keyWindow) {
                keyWindow = [UIApplication sharedApplication].keyWindow;
            }
            
            UIViewController *rootVC = keyWindow.rootViewController;
            if (!rootVC) return;
            
            UIViewController *topVC = [self topViewControllerWithRootVC:rootVC];
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

- (BOOL)hasButtonsInView:(UIView *)view {
    NSString *className = NSStringFromClass([view class]);
    if ([view isKindOfClass:[UIButton class]] || 
        [className localizedCaseInsensitiveContainsString:@"button"] || 
        [className localizedCaseInsensitiveContainsString:@"render"] || 
        [className localizedCaseInsensitiveContainsString:@"touch"]) {
        
        if (view.frame.origin.y < 100 && view.frame.size.width < 60) {
            // Bo qua nut back he thong
        } else {
            return YES;
        }
    }
    
    for (UIView *subview in view.subviews) {
        if ([self hasButtonsInView:subview]) {
            return YES;
        }
    }
    return NO;
}

- (void)detectCaptureModeByUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    for (UIWindow *w in ws.windows) { if (w.isKeyWindow) { keyWindow = w; break; } }
                }
            }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
        
        if (keyWindow && keyWindow.rootViewController) {
            UIViewController *topVC = [self topViewControllerWithRootVC:keyWindow.rootViewController];
            if (topVC && topVC.view) {
                self.isCaptureMode = [self hasButtonsInView:topVC.view];
            }
        }
    });
}
- (void)imagePickerController:(UIImagePickerController *)picker 
didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
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
                self.previewOverlayView.hidden = NO;
            });
        }
    }
    [picker dismissViewControllerAnimated:YES completion:^{
        self.isPickerOpen = NO;
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        self.isPickerOpen = NO;
    }];
}

- (CMSampleBufferRef)createFakeBuffer {
    __block UIImage *currentImg = nil;
    if ([NSThread isMainThread]) {
        currentImg = self.selectedImage;
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            currentImg = self.selectedImage;
        });
    }
    
    if (!currentImg) return NULL;
    
    CGImageRef imgRef = currentImg.CGImage;
    size_t w = CGImageGetWidth(imgRef);
    size_t h = CGImageGetHeight(imgRef);
    
    NSDictionary *opts = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    
    CVPixelBufferRef pxBuf = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)opts, &pxBuf);
    if (status != kCVReturnSuccess || !pxBuf) return NULL;
    
    CVPixelBufferLockBaseAddress(pxBuf, 0);
    void *data = CVPixelBufferGetBaseAddress(pxBuf);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef ctx = CGBitmapContextCreate(data, w, h, 8, CVPixelBufferGetBytesPerRow(pxBuf), cs, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), imgRef);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pxBuf, 0);
    
    CMVideoFormatDescriptionRef vInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pxBuf, &vInfo);
    
    if (CMTIME_IS_INVALID(self.lastPts) || CMTIME_IS_ZERO(self.lastPts)) {
        self.lastPts = CMClockGetTime(CMClockGetHostTimeClock());
    } else {
        self.lastPts = CMTimeAdd(self.lastPts, CMTimeMake(1, 30));
    }
    
    CMSampleTimingInfo tInfo;
    tInfo.duration = CMTimeMake(1, 30);
    tInfo.presentationTimeStamp = self.lastPts;
    tInfo.decodeTimeStamp = kCMTimeInvalid;
    
    CMSampleBufferRef sBuf = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pxBuf, YES, NULL, NULL, vInfo, &tInfo, &sBuf);
    
    CVPixelBufferRelease(pxBuf);
    if (vInfo) CFRelease(vInfo);
    
    return sBuf;
}
@end

%hook AVCaptureVideoPreviewLayer
- (void)setSession:(AVCaptureSession *)session {
    %orig;
    
    [[WincareFakeCamManager sharedInstance] detectCaptureModeByUI];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[WincareFakeCamManager sharedInstance] detectCaptureModeByUI];
        
        if (![WincareFakeCamManager sharedInstance].isCaptureMode) {
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
            fakeView.contentMode = UIViewContentModeScaleAspectFill;
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
    if ([WincareFakeCamManager sharedInstance].isCaptureMode && [WincareFakeCamManager sharedInstance].previewOverlayView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [WincareFakeCamManager sharedInstance].previewOverlayView.frame = bounds;
        });
    }
}
%end

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id)del queue:(dispatch_queue_t)q {
    if (del) {
        Class delClass = [del class];
        SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
        
        if ([del respondsToSelector:sel]) {
            NSString *className = NSStringFromClass(delClass);
            NSString *key = [NSString stringWithFormat:@"WincareSwizzled_%@", className];
            
            if (![objc_getAssociatedObject(delClass, (__bridge const void *)(key)) boolValue]) {
                objc_setAssociatedObject(delClass, (__bridge const void *)(key), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                
                Method m = class_getInstanceMethod(delClass, sel);
                IMP origImp = method_getImplementation(m);
                
                typedef void (*OrigFunc)(id, SEL, id, CMSampleBufferRef, id);
                __block OrigFunc orig = (OrigFunc)origImp;
                
                id block = ^(id slf, id out, CMSampleBufferRef sBuf, id conn) {
                    @autoreleasepool {
                        if ([WincareFakeCamManager sharedInstance].isCaptureMode) {
                            CMSampleBufferRef fake = [[WincareFakeCamManager sharedInstance] createFakeBuffer];
                            if (fake) {
                                orig(slf, sel, out, fake, conn);
                                CFRelease(fake);
                            } else {
                                orig(slf, sel, out, sBuf, conn);
                            }
                        } else {
                            orig(slf, sel, out, sBuf, conn);
                        }
                    }
                };
                IMP newImp = imp_implementationWithBlock(block);
                class_replaceMethod(delClass, sel, newImp, method_getTypeEncoding(m));
            }
        }
    }
    %orig(del, q);
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if ([WincareFakeCamManager sharedInstance].isCaptureMode) {
        UIImage *fake = [WincareFakeCamManager sharedInstance].selectedImage;
        if (fake) return UIImageJPEGRepresentation(fake, 0.9);
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    if ([WincareFakeCamManager sharedInstance].isCaptureMode) {
        UIImage *fake = [WincareFakeCamManager sharedInstance].selectedImage;
        if (fake) return fake.CGImage;
    }
    return %orig;
}

- (CVPixelBufferRef)pixelBuffer {
    if ([WincareFakeCamManager sharedInstance].isCaptureMode) {
        CMSampleBufferRef fakeBuf = [[WincareFakeCamManager sharedInstance] createFakeBuffer];
        if (fakeBuf) {
            CVPixelBufferRef px = CMSampleBufferGetImageBuffer(fakeBuf);
            if (px) {
                CVPixelBufferRetain(px);
                CFRelease(fakeBuf);
                return px;
            }
            CFRelease(fakeBuf);
        }
    }
    return %orig;
}
@end

%hook AVCaptureStillImageOutput
- (void)captureStillImageAsynchronouslyFromConnection:(id)conn completionHandler:(void (^)(CMSampleBufferRef, NSError *))h {
    if (!h) { %orig; return; }
    
    void (^customH)(CMSampleBufferRef, NSError *) = ^(CMSampleBufferRef sBuf, NSError *err) {
        @autoreleasepool {
            if ([WincareFakeCamManager sharedInstance].isCaptureMode) {
                CMSampleBufferRef fake = [[WincareFakeCamManager sharedInstance] createFakeBuffer];
                if (fake) {
                    h(fake, err);
                    CFRelease(fake);
                } else {
                    h(sBuf, err);
                }
            } else {
                h(sBuf, err);
            }
        }
    };
    %orig(conn, customH);
}
%end

#pragma clang diagnostic pop

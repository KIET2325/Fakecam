#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>

@interface WincareFakeCamManager : NSObject 
    <UIImagePickerControllerDelegate, 
     UINavigationControllerDelegate>
+ (instancetype)sharedInstance;
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UIImage *selectedImage;
@property (nonatomic, strong) UIImageView *previewOverlayView; 
@property (nonatomic, assign) BOOL isPickerOpen;
- (void)showPhotoPicker;
- (CMSampleBufferRef)createFakeBuffer;
- (void)processStillImage:(CMSampleBufferRef)sBuf 
                    error:(NSError *)err 
                  handler:(void (^)(CMSampleBufferRef, NSError *))h;
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

- (void)showPhotoPicker {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isPickerOpen) return;
        
        UIWindowScene *activeScene = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in 
                 [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == 
                    UISceneActivationStateForegroundActive && 
                    [scene isKindOfClass:[UIWindowScene class]]) {
                    activeScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
        if (!activeScene) return;
        self.isPickerOpen = YES;

        self.overlayWindow = [[UIWindow alloc] 
            initWithWindowScene:activeScene];
        self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 2;
        self.overlayWindow.backgroundColor = [UIColor clearColor];
        
        UIViewController *rootVC = [[UIViewController alloc] init];
        self.overlayWindow.rootViewController = rootVC;
        [self.overlayWindow makeKeyAndVisible];

        UIImagePickerController *picker = 
            [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        [rootVC presentViewController:picker 
                             animated:YES 
                           completion:nil];
    });
}

- (void)imagePickerController:(UIImagePickerController *)picker 
didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    if (img) {
        if (img.imageOrientation != UIImageOrientationUp) {
            UIGraphicsBeginImageContextWithOptions(img.size, 
                                                   NO, 
                                                   img.scale);
            [img drawInRect:CGRectMake(0, 0, 
                                       img.size.width, 
                                       img.size.height)];
            img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
        
        [WincareFakeCamManager sharedInstance].selectedImage = img;
        
        if ([WincareFakeCamManager sharedInstance].previewOverlayView) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [WincareFakeCamManager sharedInstance]
                    .previewOverlayView.image = img;
                [WincareFakeCamManager sharedInstance]
                    .previewOverlayView.hidden = NO;
            });
        }
    }
    [picker dismissViewControllerAnimated:YES completion:^{
        if (self.overlayWindow) {
            self.overlayWindow.hidden = YES;
            self.overlayWindow = nil;
        }
        self.isPickerOpen = NO;
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        if (self.overlayWindow) {
            self.overlayWindow.hidden = YES;
            self.overlayWindow = nil;
        }
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
    CVPixelBufferCreate(kCFAllocatorDefault, w, h, 
                        kCVPixelFormatType_32BGRA, 
                        (__bridge CFDictionaryRef)opts, &pxBuf);
    
    CVPixelBufferLockBaseAddress(pxBuf, 0);
    void *data = CVPixelBufferGetBaseAddress(pxBuf);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef ctx = CGBitmapContextCreate(
        data, w, h, 8, 
        CVPixelBufferGetBytesPerRow(pxBuf), 
        cs, kCGBitmapByteOrder32Little | 
        kCGImageAlphaPremultipliedFirst);
    
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), imgRef);
    CGColorSpaceRelease(cs);
    CGContextRelease(ctx);
    CVPixelBufferUnlockBaseAddress(pxBuf, 0);
    
    CMVideoFormatDescriptionRef vInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault, pxBuf, &vInfo);
    
    CMSampleTimingInfo tInfo = kCMTimingInfoInvalid;
    CMSampleBufferRef sBuf = NULL;
    
    CMSampleBufferCreateForImageBuffer(
        kCFAllocatorDefault, pxBuf, YES, 
        NULL, NULL, vInfo, &tInfo, &sBuf);
    
    CVPixelBufferRelease(pxBuf);
    CFRelease(vInfo);
    return sBuf;
}

- (void)processStillImage:(CMSampleBufferRef)sBuf 
                    error:(NSError *)err 
                  handler:(void (^)(CMSampleBufferRef, NSError *))h {
    CMSampleBufferRef fake = [self createFakeBuffer];
    if (fake) {
        h(fake, err);
        CFRelease(fake);
    } else {
        h(sBuf, err);
    }
}
@end

// ==================== HOOK GIAO DIỆN HIỂN THỊ ====================

%hook AVCaptureVideoPreviewLayer

- (void)setSession:(AVCaptureSession *)session {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *pView = nil;
        if ([self respondsToSelector:@selector(delegate)] && 
            [((id)self.delegate) isKindOfClass:[UIView class]]) {
            pView = (UIView *)self.delegate;
        }
        
        if (![WincareFakeCamManager sharedInstance].previewOverlayView) {
            UIImageView *fakeView = [[UIImageView alloc] 
                initWithFrame:self.bounds];
            fakeView.contentMode = UIViewContentModeScaleAspectFill;
            fakeView.clipsToBounds = YES;
            fakeView.hidden = YES;
            
            if (pView) {
                [pView addSubview:fakeView];
                [pView bringSubviewToFront:fakeView];
            } else {
                [self addSublayer:fakeView.layer];
            }
            [WincareFakeCamManager sharedInstance]
                .previewOverlayView = fakeView;
        }
        
        if ([WincareFakeCamManager sharedInstance].selectedImage) {
            [WincareFakeCamManager sharedInstance]
                .previewOverlayView.image = 
                [WincareFakeCamManager sharedInstance].selectedImage;
            [WincareFakeCamManager sharedInstance]
                .previewOverlayView.hidden = NO;
        }
        [[WincareFakeCamManager sharedInstance] showPhotoPicker];
    });
}

- (void)setBounds:(CGRect)bounds {
    %orig;
    if ([WincareFakeCamManager sharedInstance].previewOverlayView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [WincareFakeCamManager sharedInstance]
                .previewOverlayView.frame = bounds;
        });
    }
}
%end

// ==================== HOOK LUỒNG QUÉT MÃ VẠCH ====================

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:
    (id<AVCaptureVideoDataOutputSampleBufferDelegate>)del 
                          queue:(dispatch_queue_t)q {
    if (del) {
        Class delClass = [del class];
        SEL sel = @selector(captureOutput:
                           didOutputSampleBuffer:
                           fromConnection:);
        
        if ([del respondsToSelector:sel]) {
            static dispatch_once_t token;
            dispatch_once(&token, ^{
                Method m = class_getInstanceMethod(delClass, sel);
                IMP origImp = method_getImplementation(m);
                
                id block = ^(id slf, id out, 
                             CMSampleBufferRef sBuf, id conn) {
                    CMSampleBufferRef fake = 
                        [[WincareFakeCamManager sharedInstance] 
                            createFakeBuffer];
                    void (*orig)(id, SEL, id, 
                                 CMSampleBufferRef, id) = 
                                 (void *)origImp;
                    if (fake) {
                        orig(slf, sel, out, fake, conn);
                        CFRelease(fake);
                    } else {
                        orig(slf, sel, out, sBuf, conn);
                    }
                };
                IMP newImp = imp_implementationWithBlock(block);
                class_replaceMethod(delClass, sel, newImp, 
                                    method_getTypeEncoding(m));
            });
        }
    }
    %orig(del, q);
}
%end

// ==================== HOOK LUỒNG ẢNH CHỤP TĨNH ====================

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
- (void)captureStillImageAsynchronouslyFromConnection:(id)conn 
    completionHandler:(void (^)(CMSampleBufferRef, NSError *))h {
    if (!h) { %orig; return; }
    
    void (^customH)(CMSampleBufferRef, NSError *) = 
    [^(CMSampleBufferRef sBuf, NSError *err) {
        [[WincareFakeCamManager sharedInstance] 
            processStillImage:sBuf error:err handler:h];
    } copy];
    
    %orig(conn, customH);
}
%end

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface WincareFakeCamManager : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
+ (instancetype)sharedInstance;
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UIImage *selectedImage;
@property (nonatomic, strong) UIImageView *previewOverlayView; // View đè ảnh fake lên màn hình camera
@property (nonatomic, assign) BOOL isPickerOpen;
- (void)showPhotoPicker;
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
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    activeScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
        if (!activeScene) return;
        self.isPickerOpen = YES;

        if (@available(iOS 13.0, *)) {
            self.overlayWindow = [[UIWindow alloc] initWithWindowScene:activeScene];
        } else {
            self.overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 2;
        self.overlayWindow.backgroundColor = [UIColor clearColor];
        
        UIViewController *rootVC = [[UIViewController alloc] init];
        self.overlayWindow.rootViewController = rootVC;
        [self.overlayWindow makeKeyAndVisible];

        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        [rootVC presentViewController:picker animated:YES completion:nil];
    });
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    if (img) {
        self.selectedImage = img;
        // Nếu camera đang mở, gán trực tiếp ảnh vào màn hình preview luôn
        if (self.previewOverlayView) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.previewOverlayView.image = img;
                self.previewOverlayView.hidden = NO;
            });
        }
    }
    [picker dismissViewControllerAnimated:YES completion:^{
        if (self.overlayWindow) {
            self.overlayWindow.hidden = YES;
            self.overlayWindow = nil;
        }
        self.isPickerOpen = NO;
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        if (self.overlayWindow) {
            self.overlayWindow.hidden = YES;
            self.overlayWindow = nil;
        }
        self.isPickerOpen = NO;
    });
}
@end

// ==================== HOOK LỚP HIỂN THỊ CAMERA CỦA FLUTTER ====================

%hook AVCaptureVideoPreviewLayer

// Hàm này được gọi khi Flutter bắt đầu vẽ luồng camera lên màn hình điện thoại
- (void)setSession:(AVCaptureSession *)session {
    %orig;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Tạo một UIImageView đè khít lên khung hình camera vật lý của app
        if (![WincareFakeCamManager sharedInstance].previewOverlayView) {
            UIImageView *fakeView = [[UIImageView alloc] initWithFrame:self.bounds];
            fakeView.contentMode = UIViewContentModeScaleAspectFill;
            fakeView.clipsToBounds = YES;
            fakeView.hidden = YES;
            
            // Thêm vào lớp cha của layer camera
            [self.superlayer addSublayer:fakeView.layer]; 
            // Hoặc lưu ref để gán ảnh
            [WincareFakeCamManager sharedInstance].previewOverlayView = fakeView;
        }
        
        // Gọi trình chọn ảnh từ Album
        [[WincareFakeCamManager sharedInstance] showPhotoPicker];
    });
}

// Đảm bảo kích thước ảnh giả luôn khít với khung camera khi xoay màn hình
- (void)setBounds:(CGRect)bounds {
    %orig;
    if ([WincareFakeCamManager sharedInstance].previewOverlayView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [WincareFakeCamManager sharedInstance].previewOverlayView.frame = bounds;
        });
    }
}
%end

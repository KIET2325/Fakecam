#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface FakeCamPickerManager : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
+ (instancetype)sharedInstance;
@property (nonatomic, strong) UIWindow *overlayWindow; 
@property (nonatomic, strong) UIImageView *fakeImageView;
@property (nonatomic, assign) BOOL isPickerPresented;
- (void)triggerFakeCameraFlow;
@end

@implementation FakeCamPickerManager

+ (instancetype)sharedInstance {
    static FakeCamPickerManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[FakeCamPickerManager alloc] init];
        shared.isPickerPresented = NO;
    });
    return shared;
}

- (void)triggerFakeCameraFlow {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isPickerPresented) return;
        
        UIWindowScene *currentScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                currentScene = (UIWindowScene *)scene;
                break;
            }
        }
        
        if (!currentScene) return;
        
        self.isPickerPresented = YES;
        
        // Tạo cửa sổ độc lập nâng cao hơn lớp hiển thị của Flutter
        self.overlayWindow = [[UIWindow alloc] initWithWindowScene:currentScene];
        self.overlayWindow.frame = [UIScreen mainScreen].bounds;
        self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 1; 
        self.overlayWindow.backgroundColor = [UIColor blackColor];
        
        UIViewController *rootVC = [[UIViewController alloc] init];
        self.overlayWindow.rootViewController = rootVC;
        [self.overlayWindow makeKeyAndVisible];
        
        // Tạo view hứng ảnh hiển thị
        self.fakeImageView = [[UIImageView alloc] initWithFrame:self.overlayWindow.bounds];
        self.fakeImageView.contentMode = UIViewContentModeScaleAspectFill;
        [rootVC.view addSubview:self.fakeImageView];
        
        // Mở bộ sưu tập ảnh hệ thống công khai
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        picker.allowsEditing = NO;
        
        [rootVC presentViewController:picker animated:YES completion:nil];
    });
}

// Xử lý khi chọn ảnh xong trong Album
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *selectedImage = info[UIImagePickerControllerOriginalImage];
    
    if (selectedImage && self.fakeImageView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fakeImageView.image = selectedImage; 
        });
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

// Xử lý khi bấm nút hủy chọn ảnh
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self.overlayWindow.hidden = YES;
            self.overlayWindow = nil;
            self.isPickerPresented = NO;
        });
    }];
}

- (void)resetFakeCamera {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.overlayWindow) {
            self.overlayWindow.hidden = YES;
            self.overlayWindow = nil;
        }
        self.isPickerPresented = NO;
    });
}
@end

// ==================== HOOK PHIÊN HOẠT ĐỘNG CAMERA ====================

%hook AVCaptureSession

- (void)startRunning {
    %orig; 
    // Trễ 0.3 giây đảm bảo giao diện app gốc ổn định trước khi gọi Bộ sưu tập
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FakeCamPickerManager sharedInstance] triggerFakeCameraFlow];
    });
}

- (void)stopRunning {
    %orig;
    [[FakeCamPickerManager sharedInstance] resetFakeCamera];
}

%end

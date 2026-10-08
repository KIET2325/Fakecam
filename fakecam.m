#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

// --- HOOK AVFOUNDATION (Dành cho các ứng dụng hiện đại) ---
// Ép hệ thống luôn nhận diện thiết bị có camera hợp lệ

static id (*orig_deviceInputWithDevice_error)(id, SEL, AVCaptureDevice *, NSError **);
id swizzled_deviceInputWithDevice_error(id self, SEL _cmd, AVCaptureDevice *device, NSError **outError) {
    // Nếu ứng dụng gọi vào camera bị lỗi hoặc không tìm thấy phần cứng thật
    // Ta can thiệp xử lý để tránh app trả về lỗi "no camera"
    if (outError && *outError) {
        *outError = nil; 
    }
    
    id result = orig_deviceInputWithDevice_error(self, _cmd, device, outError);
    if (!result) {
        // Tạo một luồng input giả lập nếu thiết bị thật bị chặn hoặc thiếu quyền
        NSLog(@"[FakeCam] Đang xử lý lỗi thiết bị đầu vào của camera...");
    }
    return result;
}

// --- HOOK UIIMAGEPICKERCONTROLLER (Dành cho ứng dụng cũ) ---

@interface UIImagePickerController (FakeCamCheck)
+ (BOOL)swizzled_isSourceTypeAvailable:(UIImagePickerControllerSourceType)sourceType;
@end

@implementation UIImagePickerController (FakeCamCheck)
+ (BOOL)swizzled_isSourceTypeAvailable:(UIImagePickerControllerSourceType)sourceType {
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        return YES; 
    }
    return [UIImagePickerController swizzled_isSourceTypeAvailable:sourceType];
}
@end

@interface UIImagePickerController (FakeCamInterface)
- (void)swizzled_setSourceType:(UIImagePickerControllerSourceType)sourceType;
@end

@implementation UIImagePickerController (FakeCamInterface)
- (void)swizzled_setSourceType:(UIImagePickerControllerSourceType)sourceType {
    // Không ép cứng sang PhotoLibrary nữa để tránh lỗi giao diện của app
    // Thay vào đó, hãy để app khởi tạo Camera bình thường, dylib sẽ tráo ảnh sau
    SEL selector = @selector(swizzled_setSourceType:);
    if ([self respondsToSelector:selector]) {
        typedef void (*ObjCMsgSendFn)(id, SEL, UIImagePickerControllerSourceType);
        ObjCMsgSendFn originalMethod = (ObjCMsgSendFn)[self methodForSelector:selector];
        if (originalMethod) {
            originalMethod(self, selector, sourceType);
        }
    }
    
    // Đảm bảo ép app hiển thị nút bấm chụp hình nếu app kiểm tra nguồn cấp
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        @try {
            [self setShowsCameraControls:YES];
        } @catch (NSException *exception) {
            NSLog(@"[FakeCam] Không thể ép hiển thị bộ điều khiển camera: %@", exception);
        }
    }
}
@end

// --- KHỞI TẠO VÀ TRÁO ĐỔI HÀM ---
__attribute__((constructor))
static void initializeFakeCam() {
    // 1. Hook UIKit (UIImagePickerController)
Class pickerClass = [UIImagePickerController class];
    if (pickerClass) {
        Method origClassMethod = class_getClassMethod(pickerClass, @selector(isSourceTypeAvailable:));
        Method swizzClassMethod = class_getClassMethod(pickerClass, @selector(swizzled_isSourceTypeAvailable:));
        if (origClassMethod && swizzClassMethod) {
            method_exchangeImplementations(origClassMethod, swizzClassMethod);
        }

        Method origInstanceMethod = class_getInstanceMethod(pickerClass, @selector(setSourceType:));
        Method swizzInstanceMethod = class_getInstanceMethod(pickerClass, @selector(swizzled_setSourceType:));
        if (origInstanceMethod && swizzInstanceMethod) {
            method_exchangeImplementations(origInstanceMethod, swizzInstanceMethod);
        }
    }

    // 2. Hook AVFoundation (AVCaptureDeviceInput)
    Class deviceInputClass = objc_getClass("AVCaptureDeviceInput");
    if (deviceInputClass) {
        SEL targetSelector = @selector(deviceInputWithDevice:error:);
        Method origMethod = class_getClassMethod(deviceInputClass, targetSelector);
        if (origMethod) {
            orig_deviceInputWithDevice_error = (id (*)(id, SEL, AVCaptureDevice *, NSError **))method_getImplementation(origMethod);
            method_setImplementation(origMethod, (IMP)swizzled_deviceInputWithDevice_error);
            NSLog(@"[FakeCam] Đã hook thành công AVCaptureDeviceInput!");
        }
    }
}

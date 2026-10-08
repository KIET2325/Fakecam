#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface UIImagePickerController (FakeCam)
+ (BOOL)swizzled_isSourceTypeAvailable:(UIImagePickerControllerSourceType)sourceType;
@end

@implementation UIImagePickerController (FakeCam)

+ (BOOL)swizzled_isSourceTypeAvailable:(UIImagePickerControllerSourceType)sourceType {
    // Nếu ứng dụng yêu cầu kiểm tra Camera (Camera = 1)
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        // Trả về NO để báo ứng dụng rằng máy không có camera, ép chuyển hướng sang Photo Library
        return NO; 
    }
    // Các trường hợp khác (như chọn ảnh từ album có sẵn) giữ nguyên mặc định
    return [self swizzled_isSourceTypeAvailable:sourceType];
}

@end

// Hàm tự động chạy ngay khi file .dylib được nạp vào ứng dụng
__attribute__((constructor))
static void initializeFakeCam() {
    Class class = [UIImagePickerController class];
    SEL originalSelector = @selector(isSourceTypeAvailable:);
    SEL swizzledSelector = @selector(swizzled_isSourceTypeAvailable:);

    Method originalMethod = class_getClassMethod(class, originalSelector);
    Method swizzledMethod = class_getClassMethod(class, swizzledSelector);

    // Tiến hành tráo đổi phương thức hệ thống (Method Swizzling)
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

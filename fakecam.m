#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 1. Hook hàm kiểm tra phần cứng (Ép app tin rằng máy LUÔN CÓ camera)
@interface UIImagePickerController (FakeCamCheck)
+ (BOOL)swizzled_isSourceTypeAvailable:(UIImagePickerControllerSourceType)sourceType;
@end

@implementation UIImagePickerController (FakeCamCheck)
+ (BOOL)swizzled_isSourceTypeAvailable:(UIImagePickerControllerSourceType)sourceType {
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        return YES; // Sửa thành YES: Ép app tin là có camera vật lý
    }
    // Gọi lại hàm gốc thông qua selector đã tráo đổi để tránh lặp vô hạn
    return [UIImagePickerController swizzled_isSourceTypeAvailable:sourceType];
}
@end


// 2. Hook hàm khởi tạo giao diện (Ép app mở Album thay vì mở Camera)
@interface UIImagePickerController (FakeCamInterface)
- (void)swizzled_setSourceType:(UIImagePickerControllerSourceType)sourceType;
@end

@implementation UIImagePickerController (FakeCamInterface)
- (void)swizzled_setSourceType:(UIImagePickerControllerSourceType)sourceType {
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        // Khi app ra lệnh bật Camera, ta ép nó chuyển hướng sang chọn ảnh từ thư viện
        sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    }
    // Gọi lại hàm gốc (áp dụng cho Instance Method)
    [self swizzled_setSourceType:sourceType];
}
@end


// 3. Hàm tự động chạy để tráo đổi cả 2 hàm trên cùng lúc
__attribute__((constructor))
static void initializeFakeCam() {
    Class metaClass = objc_getMetaClass("UIImagePickerController");
    Class instanceClass = [UIImagePickerController class];

    // Tráo đổi Class Method: isSourceTypeAvailable:
    Method origClassMethod = class_getClassMethod(instanceClass, @selector(isSourceTypeAvailable:));
    Method swizzClassMethod = class_getClassMethod(instanceClass, @selector(swizzled_isSourceTypeAvailable:));
    if (origClassMethod && swizzClassMethod) {
        method_exchangeImplementations(origClassMethod, swizzClassMethod);
    }

    // Tráo đổi Instance Method: setSourceType:
    Method origInstanceMethod = class_getInstanceMethod(instanceClass, @selector(setSourceType:));
    Method swizzInstanceMethod = class_getInstanceMethod(instanceClass, @selector(swizzled_setSourceType:));
    if (origInstanceMethod && swizzInstanceMethod) {
        method_exchangeImplementations(origInstanceMethod, swizzInstanceMethod);
    }
}

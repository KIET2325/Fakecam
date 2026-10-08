#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface UIImagePickerController (FakeCamCheck)
+ (BOOL)swizzled_isSourceTypeAvailable:(UIImagePickerControllerSourceType)sourceType;
@end

@implementation UIImagePickerController (FakeCamCheck)
+ (BOOL)swizzled_isSourceTypeAvailable:(UIImagePickerControllerSourceType)sourceType {
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        return YES; // Báo cho app là máy luôn có camera
    }
    return [UIImagePickerController swizzled_isSourceTypeAvailable:sourceType];
}
@end

@interface UIImagePickerController (FakeCamInterface)
- (void)swizzled_setSourceType:(UIImagePickerControllerSourceType)sourceType;
@end

@implementation UIImagePickerController (FakeCamInterface)
- (void)swizzled_setSourceType:(UIImagePickerControllerSourceType)sourceType {
    // Nếu ứng dụng muốn bật Camera, ép chuyển hướng sang Photo Library an toàn
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    }
    
    // Gọi hàm gốc thông qua cơ chế kiểm tra selector để chống crash trên iOS mới
    SEL selector = @selector(swizzled_setSourceType:);
    if ([self respondsToSelector:selector]) {
        typedef void (*ObjCMsgSendFn)(id, SEL, UIImagePickerControllerSourceType);
        ObjCMsgSendFn originalMethod = (ObjCMsgSendFn)[self methodForSelector:selector];
        if (originalMethod) {
            originalMethod(self, selector, sourceType);
        }
    }
}
@end

__attribute__((constructor))
static void initializeFakeCam() {
    Class instanceClass = [UIImagePickerController class];
    if (!instanceClass) return;

    // Tráo đổi Class Method (Kiểm tra phần cứng)
    Method origClassMethod = class_getClassMethod(instanceClass, @selector(isSourceTypeAvailable:));
    Method swizzClassMethod = class_getClassMethod(instanceClass, @selector(swizzled_isSourceTypeAvailable:));
    if (origClassMethod && swizzClassMethod) {
        method_exchangeImplementations(origClassMethod, swizzClassMethod);
    }

    // Tráo đổi Instance Method (Giao diện hiển thị)
    Method origInstanceMethod = class_getInstanceMethod(instanceClass, @selector(setSourceType:));
    Method swizzInstanceMethod = class_getInstanceMethod(instanceClass, @selector(swizzled_setSourceType:));
    if (origInstanceMethod && swizzInstanceMethod) {
        method_exchangeImplementations(origInstanceMethod, swizzInstanceMethod);
    }
}

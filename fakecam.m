#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

// Hook luồng hiển thị để đè ảnh fake lên màn hình cam mà không làm văng app
static void (*orig_setSession)(id, SEL, AVCaptureSession *);
void swizzled_setSession(id self, SEL _cmd, AVCaptureSession *session) {
    orig_setSession(self, _cmd, session);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *previewView = (UIView *)self;
        if ([previewView isKindOfClass:[UIView class]]) {
            if (![previewView viewWithTag:9999]) {
                // ĐƯỜNG DẪN ĐẾN THƯ MỤC DOCUMENTS (Nơi bạn có thể tự thay ảnh bằng app Tệp)
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *docsDir = [paths objectAtIndex:0];
                NSString *imgPath = [docsDir stringByAppendingPathComponent:@"fake_photo.jpg"];
                
                UIImage *fakeImg = [UIImage imageWithContentsOfFile:imgPath];
                if (fakeImg) {
                    UIImageView *fakeImageView = [[UIImageView alloc] initWithImage:fakeImg];
                    fakeImageView.frame = previewView.bounds;
                    fakeImageView.contentMode = UIViewContentModeScaleAspectFill;
                    fakeImageView.tag = 9999;
                    [previewView addSubview:fakeImageView];
                }
            }
        }
    });
}

__attribute__((constructor))
static void initializeFakeCam() {
    Class previewLayerClass = objc_getClass("AVCaptureVideoPreviewLayer");
    if (previewLayerClass) {
        SEL setSessionSelector = @selector(setSession:);
        Method origMethod = class_getInstanceMethod(previewLayerClass, setSessionSelector);
        if (origMethod) {
            orig_setSession = (void (*)(id, SEL, AVCaptureSession *))method_getImplementation(origMethod);
            method_setImplementation(origMethod, (IMP)swizzled_setSession);
        }
    }
}

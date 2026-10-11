TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WINCAREFakeCam

WINCAREFakeCam_FILES = Tweak.xm
WINCAREFakeCam_FRAMEWORKS = UIKit AVFoundation CoreMedia

include $(THEOS)/makefiles/tweak.mk

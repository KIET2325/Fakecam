TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = libfakecampicker

libfakecampicker_FILES = Tweak.xm
# Cập nhật lại danh sách Frameworks chuẩn cho mã nguồn mới
libfakecampicker_FRAMEWORKS = UIKit AVFoundation CoreGraphics Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

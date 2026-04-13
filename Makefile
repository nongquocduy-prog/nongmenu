TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = NongMenu

NongMenu_FILES = NongMenu.m
NongMenu_FRAMEWORKS = UIKit Foundation QuartzCore
NongMenu_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/library.mk

TARGET := iphone:clang:16.5:15.0
ARCHS := arm64
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := DeviceSpoof

DeviceSpoof_FILES := Tweak.x src/DSPProfile.m src/DSPShopeeReport.m
DeviceSpoof_CFLAGS := -fobjc-arc -Isrc
DeviceSpoof_FRAMEWORKS := UIKit Security Foundation CoreFoundation CoreGraphics
DeviceSpoof_INSTALL_PATH := /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

before-package::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/var/jb/usr/lib/TweakInject$(ECHO_END)
	$(ECHO_NOTHING)cp $(THEOS_STAGING_DIR)/var/jb/Library/MobileSubstrate/DynamicLibraries/DeviceSpoof.dylib $(THEOS_STAGING_DIR)/var/jb/usr/lib/TweakInject/$(ECHO_END)
	$(ECHO_NOTHING)cp $(THEOS_STAGING_DIR)/var/jb/Library/MobileSubstrate/DynamicLibraries/DeviceSpoof.plist $(THEOS_STAGING_DIR)/var/jb/usr/lib/TweakInject/$(ECHO_END)

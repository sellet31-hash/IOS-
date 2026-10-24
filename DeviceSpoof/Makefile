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
	bash ./copy-tweakinject.sh "$(THEOS_STAGING_DIR)"

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

# stage finishes before before-package. Rootless moves files under /var/jb only
# inside internal-package, so the dylib is still at staging/Library/... here.
before-package::
	@set -e; \
	libdir="$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries"; \
	inject="$(THEOS_STAGING_DIR)/usr/lib/TweakInject"; \
	if [ ! -f "$$libdir/DeviceSpoof.dylib" ]; then \
	  libdir="$(THEOS_STAGING_DIR)/var/jb/Library/MobileSubstrate/DynamicLibraries"; \
	  inject="$(THEOS_STAGING_DIR)/var/jb/usr/lib/TweakInject"; \
	fi; \
	if [ ! -f "$$libdir/DeviceSpoof.dylib" ]; then \
	  echo "DeviceSpoof dylib missing from staging:"; \
	  find "$(THEOS_STAGING_DIR)" -name 'DeviceSpoof.*' -print; \
	  exit 1; \
	fi; \
	mkdir -p "$$inject"; \
	cp "$$libdir/DeviceSpoof.dylib" "$$libdir/DeviceSpoof.plist" "$$inject/"

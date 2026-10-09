TARGET := iphone:clang:latest:15.0
ARCHS := arm64
INSTALL_TARGET_PROCESSES := AppBackup

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := AppBackup

AppBackup_FILES := \
	src/main.m \
	src/ABAppDelegate.m \
	src/ABModels.m \
	src/ABIcon.m \
	src/ABAppLibrary.m \
	src/ABTarArchive.m \
	src/ABBackupEngine.m \
	src/ABProgressOverlay.m \
	src/ABBackupActions.m \
	src/ABAppListViewController.m \
	src/ABAppDetailViewController.m \
	src/ABBackupListViewController.m \
	src/abtar.c

AppBackup_FRAMEWORKS := UIKit CoreGraphics QuartzCore
AppBackup_CFLAGS := -fobjc-arc -Isrc -Wno-deprecated-declarations -Wno-unused-command-line-argument
AppBackup_CODESIGN_FLAGS := -Sentitlements.plist
AppBackup_INSTALL_PATH := /Applications

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	THEOS_STAGING_DIR="$(THEOS_STAGING_DIR)" bash scripts/make-ipa.sh

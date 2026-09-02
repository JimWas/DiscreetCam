export THEOS ?= /Users/jimwashkau/theos
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JimWasRecorder
JimWasRecorder_FILES = Tweak.xm JWRRecorderManager.m JWRPreferences.m JWRLogger.m
JimWasRecorder_FRAMEWORKS = AVFoundation AVFAudio Photos AudioToolbox UIKit
JimWasRecorder_CFLAGS = -fobjc-arc
JimWasRecorder_LDFLAGS = -Wl,-undefined,dynamic_lookup

APPLICATION_NAME = JWRRecorderApp
JWRRecorderApp_FILES = app/main.m app/JWRAppDelegate.m JWRRecorderManager.m JWRPreferences.m JWRLogger.m JWRLocationProvider.m
JWRRecorderApp_FRAMEWORKS = AVFoundation Photos CoreLocation AudioToolbox UIKit
JWRRecorderApp_CFLAGS = -fobjc-arc
JWRRecorderApp_INSTALL_PATH = /Applications
JWRRecorderApp_CODESIGN_FLAGS = -Sapp/JWRRecorderApp.entitlements
JWRRecorderApp_RESOURCE_FILES = app/JWRBlackVideo.mov app/Icons/AppIcon60x60@2x.png app/Icons/AppIcon60x60@3x.png app/Icons/AppIcon29x29@2x.png app/Icons/AppIcon29x29@3x.png app/Icons/AppIcon20x20@2x.png app/Icons/AppIcon20x20@3x.png

BUNDLE_NAME = JimWasRecorderPrefs
JimWasRecorderPrefs_FILES = prefs/JWRRootListController.m JWRPreferences.m JWRLogger.m
JimWasRecorderPrefs_FRAMEWORKS = UIKit AVFoundation
JimWasRecorderPrefs_PRIVATE_FRAMEWORKS = Preferences
JimWasRecorderPrefs_INSTALL_PATH = /Library/PreferenceBundles
JimWasRecorderPrefs_CFLAGS = -fobjc-arc
JimWasRecorderPrefs_RESOURCE_DIRS = prefs/Resources
JimWasRecorderPrefs_INFO_PLIST = prefs/JimWasRecorderPrefs.plist

BUNDLE_NAME += JWRVideoModule
JWRVideoModule_FILES = modules/JWRVideoModule.m JWRLogger.m
JWRVideoModule_FRAMEWORKS = UIKit
JWRVideoModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
JWRVideoModule_INSTALL_PATH = /Library/ControlCenter/Bundles
JWRVideoModule_CFLAGS = -fobjc-arc
JWRVideoModule_INFO_PLIST = modules/JWRVideoModule.plist

BUNDLE_NAME += JWRAudioModule
JWRAudioModule_FILES = modules/JWRAudioModule.m JWRLogger.m
JWRAudioModule_FRAMEWORKS = UIKit
JWRAudioModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
JWRAudioModule_INSTALL_PATH = /Library/ControlCenter/Bundles
JWRAudioModule_CFLAGS = -fobjc-arc
JWRAudioModule_INFO_PLIST = modules/JWRAudioModule.plist

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "sbreload"

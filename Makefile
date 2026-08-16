ARCHS = arm64
TARGET := iphone:clang:16.5:14.0
include $(THEOS)/makefiles/common.mk
DEBUG = 1

TWEAK_NAME = PrimeFreeBird

NFB_NAME := $(shell sed -n 's/^Name: //p' control)
NFB_VERSION := $(shell sed -n 's/^Version: //p' control)
NFB_COMMIT := $(shell git rev-parse --short HEAD)

# Regenerate the hook manifest from the current source on every build, before
# the file list below is evaluated, so the debugger's health check always
# matches the code that shipped. Hand-editing it would defeat its purpose.
NFB_MANIFEST := $(shell python3 tools/gen-hook-manifest.py 2>/dev/null && echo done)

PrimeFreeBird_FILES = $(shell find src \( -name '*.x' -o -name '*.m' \) | sort)
PrimeFreeBird_FRAMEWORKS = UIKit Foundation AVFoundation AVKit CoreMotion GameController VideoToolbox Accelerate CoreMedia CoreVideo CoreImage CoreGraphics ImageIO Photos CoreServices SystemConfiguration SafariServices Security QuartzCore WebKit SceneKit
PrimeFreeBird_PRIVATE_FRAMEWORKS = Preferences
PrimeFreeBird_EXTRA_FRAMEWORKS = Cephei CepheiPrefs CepheiUI
PrimeFreeBird_OBJ_FILES = $(shell find deps/ffmpeg-kit-next/build/lib -name '*.a')
PrimeFreeBird_CFLAGS = -Isrc -Ideps/ffmpeg-kit-next/build -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unused-function -Wno-unused-property-ivar -Wno-error -DNFB_VERSION_STRING='"$(NFB_NAME) v$(NFB_VERSION)"' -DNFB_PRODUCT_NAME='"$(NFB_NAME)"' -DNFB_COMMIT_STRING='"$(NFB_COMMIT)"'

include $(THEOS_MAKE_PATH)/tweak.mk

ifdef SIDELOADED
SUBPROJECTS += deps/flex deps/zxPluginsInject/upstream
else
SUBPROJECTS += deps/flex
endif

include $(THEOS_MAKE_PATH)/aggregate.mk

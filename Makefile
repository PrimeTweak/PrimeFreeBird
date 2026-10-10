ARCHS = arm64
TARGET := iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PrimeFreeBird

PFB_NAME := $(shell sed -n 's/^Name: //p' control)
PFB_VERSION := $(shell sed -n 's/^Version: //p' control)
PFB_COMMIT := $(shell git rev-parse --short HEAD)

# The hook manifest is regenerated from the source on every build, before the file
# list is read, so the health check matches the shipped code; a failure stops the build.
PFB_MANIFEST := $(shell python3 tools/gen-hook-manifest.py >/dev/null && echo done)
ifneq ($(PFB_MANIFEST),done)
$(error hook manifest generation failed - see the error above; python3 is required)
endif

PrimeFreeBird_FILES = $(shell find src \( -name '*.x' -o -name '*.m' \) | sort)
PrimeFreeBird_FRAMEWORKS = UIKit Foundation AVFoundation AVKit CoreMotion GameController VideoToolbox Accelerate CoreMedia CoreVideo CoreImage CoreGraphics ImageIO Photos CoreServices SystemConfiguration SafariServices Security QuartzCore WebKit SceneKit
PrimeFreeBird_PRIVATE_FRAMEWORKS = Preferences
PrimeFreeBird_EXTRA_FRAMEWORKS = Cephei CepheiPrefs CepheiUI
PrimeFreeBird_OBJ_FILES = $(shell find deps/ffmpeg-kit-next/build/lib -name '*.a')
PrimeFreeBird_CFLAGS = -Isrc -Ideps/ffmpeg-kit-next/build -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unused-function -Wno-unused-property-ivar -Wno-error -DPFB_VERSION_STRING='"$(PFB_NAME) $(PFB_VERSION)"' -DPFB_PRODUCT_NAME='"$(PFB_NAME)"' -DPFB_COMMIT_STRING='"$(PFB_COMMIT)"'

include $(THEOS_MAKE_PATH)/tweak.mk

ifdef SIDELOADED
SUBPROJECTS += deps/flex deps/zxPluginsInject/upstream
else
SUBPROJECTS += deps/flex
endif

include $(THEOS_MAKE_PATH)/aggregate.mk

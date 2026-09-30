TARGET := iphone:clang:latest:14.0
ARCHS := arm64

# fleXD, Tim Oliver's iOS 26 fork of FLEX, pinned to one tag and cloned while make
# parses this file, so the first build finds its sources; the clone is not tracked.
FLEX_ROOT := fleXD
FLEX_REPO := https://github.com/TimOliver/fleXD
FLEX_TAG := 6.2.0
FLEX_FETCHED := $(shell if [ ! -d "$(FLEX_ROOT)/Classes" ]; then \
	rm -rf "$(FLEX_ROOT)"; \
	git clone --quiet --depth 1 --branch "$(FLEX_TAG)" "$(FLEX_REPO)" "$(FLEX_ROOT)" >&2 \
	|| git clone --quiet --depth 1 "$(FLEX_REPO)" "$(FLEX_ROOT)" >&2; fi; \
	[ -d "$(FLEX_ROOT)/Classes" ] && echo yes || echo no)
ifneq ($(FLEX_FETCHED),yes)
$(error fleXD could not be fetched into deps/flex/$(FLEX_ROOT))
endif

# fleXD needs the iOS 26 SDK (it names UIGlassEffect): without one in sdks/, Xcode's is
# linked in for "latest" above. Only this subproject builds against it.
FLEX_SDK := $(shell if ! ls -d "$(THEOS)"/sdks/iPhoneOS2[6-9]*.sdk >/dev/null 2>&1; then \
	sdk="$$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)"; \
	ver="$$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)"; \
	if [ -n "$$sdk" ] && [ -n "$$ver" ]; then ln -sfn "$$sdk" "$(THEOS)/sdks/iPhoneOS$$ver.sdk"; fi; fi; \
	ls -d "$(THEOS)"/sdks/iPhoneOS*.sdk 2>/dev/null | sed 's/.*iPhoneOS//; s/\.sdk//' | sort -V | tail -1)

include $(THEOS)/makefiles/common.mk

SOURCES := $(shell find $(FLEX_ROOT)/Classes \( -name '*.c' -o -name '*.m' -o -name '*.mm' \))
IMPORTS := $(addprefix -I,$(shell find $(FLEX_ROOT)/Classes -type d))

TWEAK_NAME := libpfbFLEX

$(TWEAK_NAME)_FILES := $(SOURCES)
$(TWEAK_NAME)_FRAMEWORKS := CoreGraphics UIKit ImageIO QuartzCore
$(TWEAK_NAME)_LIBRARIES := sqlite3 z
$(TWEAK_NAME)_CFLAGS := -fobjc-arc -w $(IMPORTS)
$(TWEAK_NAME)_CCFLAGS := -std=gnu++11

include $(THEOS_MAKE_PATH)/tweak.mk

before-all::
	@echo "libpfbFLEX: fleXD $(FLEX_TAG), $(words $(SOURCES)) sources, SDK $(FLEX_SDK)"

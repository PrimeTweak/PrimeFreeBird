TARGET := iphone:clang:latest:14.0
ARCHS := arm64

# fleXD - Tim Oliver's fork of FLEX, redrawn for iOS 26 - pinned to one tag.
# Fetched here rather than kept as a submodule: the tree is not tracked, so
# switching or bumping it never touches git. The clone runs while make parses
# this file, before SOURCES is computed, so the first build finds the sources.
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

# fleXD names UIGlassEffect directly, so it needs the iOS 26 SDK to compile.
# When the sdks folder holds nothing that new, Xcode's own SDK is linked in
# under its version, and "latest" above picks it up. The root Makefile keeps
# its own TARGET; only this subproject builds against the newer SDK.
FLEX_SDK := $(shell if ! ls -d "$(THEOS)"/sdks/iPhoneOS2[6-9]*.sdk >/dev/null 2>&1; then \
	sdk="$$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)"; \
	ver="$$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)"; \
	if [ -n "$$sdk" ] && [ -n "$$ver" ]; then ln -sfn "$$sdk" "$(THEOS)/sdks/iPhoneOS$$ver.sdk"; fi; fi; \
	ls -d "$(THEOS)"/sdks/iPhoneOS*.sdk 2>/dev/null | sed 's/.*iPhoneOS//; s/\.sdk//' | sort -V | tail -1)

include $(THEOS)/makefiles/common.mk

SOURCES := $(shell find $(FLEX_ROOT)/Classes \( -name '*.c' -o -name '*.m' -o -name '*.mm' \))
IMPORTS := $(addprefix -I,$(shell find $(FLEX_ROOT)/Classes -type d))

TWEAK_NAME := libbhFLEX

$(TWEAK_NAME)_FILES := $(SOURCES)
$(TWEAK_NAME)_FRAMEWORKS := CoreGraphics UIKit ImageIO QuartzCore
$(TWEAK_NAME)_LIBRARIES := sqlite3 z
$(TWEAK_NAME)_CFLAGS := -fobjc-arc -w $(IMPORTS)
$(TWEAK_NAME)_CCFLAGS := -std=gnu++11

include $(THEOS_MAKE_PATH)/tweak.mk

before-all::
	@echo "libbhFLEX: fleXD $(FLEX_TAG), $(words $(SOURCES)) sources, SDK $(FLEX_SDK)"

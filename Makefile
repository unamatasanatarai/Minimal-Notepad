# Makefile for Minimal Notepad macOS Application

PRODUCT_NAME = MinimalNotepad
BUILD_DIR = build
APP_DIR = $(BUILD_DIR)/Minimal Notepad.app
APP_TARGET = $(BUILD_DIR)/Minimal\ Notepad.app
CONTENTS_DIR = $(APP_DIR)/Contents

SWIFT_FILES = main.swift
SWIFT_FLAGS = -O

INFO_PLIST = Resources/Info.plist
APP_ICON = Resources/AppIcon.icns
ICON_SET = Resources/MinimalNotepad.iconset

.PHONY: all clean run icons

all: $(APP_TARGET)

$(APP_TARGET): $(SWIFT_FILES) $(INFO_PLIST) $(APP_ICON)
	mkdir -p "$(CONTENTS_DIR)/MacOS" "$(CONTENTS_DIR)/Resources"
	swiftc $(SWIFT_FLAGS) $(SWIFT_FILES) -o "$(CONTENTS_DIR)/MacOS/$(PRODUCT_NAME)"
	cp $(INFO_PLIST) "$(CONTENTS_DIR)/Info.plist"
	cp $(APP_ICON) "$(CONTENTS_DIR)/Resources/AppIcon.icns"
	printf 'APPL????' > "$(CONTENTS_DIR)/PkgInfo"
	codesign --force --sign - --options runtime "$(APP_DIR)"
	touch "$(APP_DIR)"
	@echo "Build successful: $(APP_DIR)"

run: all
	open "$(APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)"

# Regenerates the iconset and AppIcon.icns from icon_512x512@2x.png; run manually when the artwork changes.
icons:
	sips -z 16 16     $(ICON_SET)/icon_512x512@2x.png --out $(ICON_SET)/icon_16x16.png
	sips -z 32 32     $(ICON_SET)/icon_512x512@2x.png --out $(ICON_SET)/icon_16x16@2x.png
	sips -z 32 32     $(ICON_SET)/icon_512x512@2x.png --out $(ICON_SET)/icon_32x32.png
	sips -z 64 64     $(ICON_SET)/icon_512x512@2x.png --out $(ICON_SET)/icon_32x32@2x.png
	sips -z 128 128   $(ICON_SET)/icon_512x512@2x.png --out $(ICON_SET)/icon_128x128.png
	sips -z 256 256   $(ICON_SET)/icon_512x512@2x.png --out $(ICON_SET)/icon_128x128@2x.png
	sips -z 256 256   $(ICON_SET)/icon_512x512@2x.png --out $(ICON_SET)/icon_256x256.png
	sips -z 512 512   $(ICON_SET)/icon_512x512@2x.png --out $(ICON_SET)/icon_256x256@2x.png
	sips -z 512 512   $(ICON_SET)/icon_512x512@2x.png --out $(ICON_SET)/icon_512x512.png
	iconutil -c icns $(ICON_SET) -o $(APP_ICON)

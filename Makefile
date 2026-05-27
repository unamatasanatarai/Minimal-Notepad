# Makefile for Minimal Notepad macOS Application

PRODUCT_NAME = MinimalNotepad
APP_NAME = Minimal Notepad.app
BUILD_DIR = build
CONTENTS_DIR = $(BUILD_DIR)/$(APP_NAME)/Contents
MACSOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

SWIFT_FILES = main.swift
SWIFT_FLAGS = -O

.PHONY: all clean run icons

all: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): icons $(SWIFT_FILES)
	@echo "Creating application bundle directories..."
	mkdir -p "$(MACSOS_DIR)"
	mkdir -p "$(RESOURCES_DIR)"
	
	@echo "Compiling Swift executable..."
	swiftc $(SWIFT_FLAGS) $(SWIFT_FILES) -o "$(MACSOS_DIR)/$(PRODUCT_NAME)"
	
	@if [ -f AppIcon.icns ]; then \
		echo "Copying application icon..."; \
		cp AppIcon.icns "$(RESOURCES_DIR)/AppIcon.icns"; \
	fi
	
	@echo "Generating PkgInfo..."
	echo "APPL????" > "$(CONTENTS_DIR)/PkgInfo"
	
	@echo "Creating Info.plist..."
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > "$(CONTENTS_DIR)/Info.plist"
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '<plist version="1.0">' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '<dict>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>CFBundleDevelopmentRegion</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>en</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>CFBundleExecutable</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>$(PRODUCT_NAME)</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>CFBundleIdentifier</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>com.minimal.notepad</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>CFBundleInfoDictionaryVersion</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>6.0</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>CFBundleName</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>Minimal Notepad</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>CFBundlePackageType</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>APPL</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>CFBundleShortVersionString</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>1.0</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>CFBundleVersion</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>1</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>LSMinimumSystemVersion</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>11.0</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <key>NSPrincipalClass</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <string>NSApplication</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@if [ -f AppIcon.icns ]; then \
		echo '    <key>CFBundleIconFile</key>' >> "$(CONTENTS_DIR)/Info.plist"; \
		echo '    <string>AppIcon</string>' >> "$(CONTENTS_DIR)/Info.plist"; \
	fi
	@echo '    <key>CFBundleDocumentTypes</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    <array>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '        <dict>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '            <key>CFBundleTypeName</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '            <string>Plain Text</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '            <key>CFBundleTypeRole</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '            <string>Editor</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '            <key>LSHandlerRank</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '            <string>Alternate</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '            <key>LSItemContentTypes</key>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '            <array>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '                <string>public.data</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '                <string>public.item</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '                <string>public.content</string>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '            </array>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '        </dict>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '    </array>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '</dict>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo '</plist>' >> "$(CONTENTS_DIR)/Info.plist"
	@echo "Build successful: $(BUILD_DIR)/$(APP_NAME)"
	@touch build/Minimal\ Notepad.app

run: all
	open "$(BUILD_DIR)/$(APP_NAME)"

clean:
	rm -rf "$(BUILD_DIR)"

icons:
	sips -z 16 16     MinimalNotepad.iconset/icon_512x512@2x.png --out MinimalNotepad.iconset/icon_16x16.png
	sips -z 32 32     MinimalNotepad.iconset/icon_512x512@2x.png --out MinimalNotepad.iconset/icon_16x16@2x.png
	sips -z 32 32     MinimalNotepad.iconset/icon_512x512@2x.png --out MinimalNotepad.iconset/icon_32x32.png
	sips -z 64 64     MinimalNotepad.iconset/icon_512x512@2x.png --out MinimalNotepad.iconset/icon_32x32@2x.png
	sips -z 128 128   MinimalNotepad.iconset/icon_512x512@2x.png --out MinimalNotepad.iconset/icon_128x128.png
	sips -z 256 256   MinimalNotepad.iconset/icon_512x512@2x.png --out MinimalNotepad.iconset/icon_128x128@2x.png
	sips -z 256 256   MinimalNotepad.iconset/icon_512x512@2x.png --out MinimalNotepad.iconset/icon_256x256.png
	sips -z 512 512   MinimalNotepad.iconset/icon_512x512@2x.png --out MinimalNotepad.iconset/icon_256x256@2x.png
	sips -z 512 512   MinimalNotepad.iconset/icon_512x512@2x.png --out MinimalNotepad.iconset/icon_512x512.png
	iconutil -c icns MinimalNotepad.iconset -o AppIcon.icns
	touch build/Minimal\ Notepad.app

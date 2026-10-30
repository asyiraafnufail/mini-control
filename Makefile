APP_NAME = MiniControl
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

DMG_NAME = $(APP_NAME).dmg
DMG_TMP = .dmg_tmp

.PHONY: all build app run clean install-helper dmg icon

all: app

SDK_PATH = $(shell xcrun --show-sdk-path 2>/dev/null)
SWIFT_FILES = $(shell find Sources/MiniControl -name "*.swift")

icon:
	@swift scripts/generate_icon.swift

build:
	@mkdir -p $(BUILD_DIR)
	@echo "Compiling $(APP_NAME) with swiftc (SDK: $(SDK_PATH))..."
	swiftc -O \
		-sdk $(SDK_PATH) \
		-target x86_64-apple-macos13.0 \
		-framework AppKit \
		-framework IOKit \
		-framework ServiceManagement \
		$(SWIFT_FILES) \
		-o $(BUILD_DIR)/$(APP_NAME)

app: build
	@echo "Bundling $(APP_BUNDLE)..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	@cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)
	@cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	@if [ -d "Resources/DisableTurboBoost.kext" ]; then \
		cp -R Resources/DisableTurboBoost.kext $(RESOURCES_DIR)/; \
	fi
	@if [ -f "Resources/AppIcon.icns" ]; then \
		cp Resources/AppIcon.icns $(RESOURCES_DIR)/; \
	fi
	@echo "Signing $(APP_BUNDLE) with ad-hoc signature..."
	@codesign --force --deep --sign - $(APP_BUNDLE) 2>/dev/null || true
	@echo "Build successful: $(APP_BUNDLE)"

dmg: app
	@echo "Creating production installer $(DMG_NAME)..."
	@rm -rf $(DMG_TMP) $(DMG_NAME)
	@mkdir -p $(DMG_TMP)
	@cp -R $(APP_BUNDLE) $(DMG_TMP)/
	@ln -s /Applications $(DMG_TMP)/Applications
	@hdiutil create -volname "$(APP_NAME)" -srcfolder $(DMG_TMP) -ov -format UDZO $(DMG_NAME)
	@rm -rf $(DMG_TMP)
	@echo "Ready for distribution: $(DMG_NAME)"

run: app
	@pkill $(APP_NAME) 2>/dev/null || true
	open $(APP_BUNDLE)

install-helper:
	@chmod +x scripts/tb_toggle.sh scripts/install_helper.sh
	@sudo ./scripts/install_helper.sh

clean:
	rm -rf .build $(APP_BUNDLE) $(DMG_NAME) $(DMG_TMP)

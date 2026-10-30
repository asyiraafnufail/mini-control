APP_NAME = MiniControl
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

.PHONY: all build app run clean

all: app

SDK_PATH = $(shell xcrun --show-sdk-path 2>/dev/null)
SWIFT_FILES = $(shell find Sources/MiniControl -name "*.swift")

build:
	@mkdir -p $(BUILD_DIR)
	@echo "Compiling $(APP_NAME) with swiftc (SDK: $(SDK_PATH))..."
	swiftc -O \
		-sdk $(SDK_PATH) \
		-target x86_64-apple-macos13.0 \
		-framework AppKit \
		-framework IOKit \
		$(SWIFT_FILES) \
		-o $(BUILD_DIR)/$(APP_NAME)

app: build
	@echo "Bundling $(APP_BUNDLE)..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	@cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)
	@cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	@echo "Build successful: $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

clean:
	rm -rf .build $(APP_BUNDLE)

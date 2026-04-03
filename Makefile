SHELL := /bin/zsh
BUILD_DIR := .build
APP_NAME := CodeIsland
BRIDGE_NAME := code-island-bridge
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app

SWIFTC := swiftc
SWIFT_FLAGS := -target arm64-apple-macosx14.0

SHARED_SOURCES := $(wildcard Sources/Shared/*.swift)
BRIDGE_SOURCES := $(wildcard Sources/Bridge/*.swift)

# Recursively find all Swift files under Sources/CodeIsland
APP_SOURCES := $(shell find Sources/CodeIsland -name '*.swift')

.PHONY: all clean bridge app bundle run

all: bridge app

# Build the bridge CLI binary
bridge: $(BUILD_DIR)/$(BRIDGE_NAME)

$(BUILD_DIR)/$(BRIDGE_NAME): $(BRIDGE_SOURCES) $(SHARED_SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFT_FLAGS) \
		$(SHARED_SOURCES) $(BRIDGE_SOURCES) \
		-o $(BUILD_DIR)/$(BRIDGE_NAME)
	@echo "✓ Built $(BRIDGE_NAME)"

# Build the main app binary
app: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): $(APP_SOURCES) $(SHARED_SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFT_FLAGS) \
		-framework AppKit \
		-framework SwiftUI \
		$(SHARED_SOURCES) $(APP_SOURCES) \
		-o $(BUILD_DIR)/$(APP_NAME)
	@echo "✓ Built $(APP_NAME)"

# Create .app bundle
bundle: app bridge
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp $(BUILD_DIR)/$(BRIDGE_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@test -f Resources/AppIcon.icns && cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/ || true
	@echo "✓ Created $(APP_BUNDLE)"

# Run the app
run: bundle
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR)

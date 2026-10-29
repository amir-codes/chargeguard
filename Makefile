# ChargeGuard build entry points. Everything except `make test` needs macOS with Xcode and XcodeGen.
#
#   make build           generate the Xcode project if it is missing (or project.yml changed), build
#                        Release into build/ (build/ChargeGuard.app, build/chargectl)
#   make project         regenerate ChargeGuard.xcodeproj (run it after adding or removing source files)
#   make test            swift test for ChargeGuardCore (any OS with Swift) and ChargeGuardSystem (macOS only)
#   make run             build and open build/ChargeGuard.app
#   make run-sim         build and open the app with --simulate (no helper, no SMC writes)
#   make install-helper  fallback helper install (runs sudo, asks for your password)
#   make uninstall       restore charging, then remove the helper and its data (runs sudo)
#   make dmg             build/ChargeGuard.dmg
#   make clean
#
# Nothing else runs sudo.

PROJECT  := ChargeGuard.xcodeproj
PBXPROJ  := $(PROJECT)/project.pbxproj
SCHEME   := ChargeGuard
CONFIG   ?= Release
BUILD    := build
DERIVED  := $(BUILD)/DerivedData
PRODUCTS := $(DERIVED)/Build/Products/$(CONFIG)
APP      := $(BUILD)/ChargeGuard.app
UNAME    := $(shell uname -s 2>/dev/null)

# Apple Development certificate when one is in the keychain, otherwise ad-hoc ("-").
ifeq ($(UNAME),Darwin)
IDENTITY := $(or $(shell /bin/bash scripts/signing.sh identity 2>/dev/null),-)
TEAM     := $(shell /bin/bash scripts/signing.sh team 2>/dev/null)
else
IDENTITY := -
TEAM     :=
endif

XCODEGEN_CHECK := command -v xcodegen >/dev/null 2>&1 || { echo "XcodeGen is missing. Install it with: brew install xcodegen"; exit 1; }

.PHONY: all project build test test-core test-system run run-sim install-helper uninstall dmg clean signing-info

all: build

# Generated when missing or older than project.yml. `touch` because XcodeGen may skip writing an unchanged file.
$(PBXPROJ): project.yml
	@$(XCODEGEN_CHECK)
	xcodegen generate
	@touch "$(PBXPROJ)"

project:
	@$(XCODEGEN_CHECK)
	xcodegen generate

signing-info:
	@echo "Code signing identity: $(IDENTITY)"
	@echo "Team: $(if $(TEAM),$(TEAM),none (ad-hoc))"

build: $(PBXPROJ) signing-info
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination 'generic/platform=macOS' \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(IDENTITY)" DEVELOPMENT_TEAM="$(TEAM)" \
		build
	rm -rf "$(APP)"
	ditto "$(PRODUCTS)/ChargeGuard.app" "$(APP)"
	ditto "$(PRODUCTS)/chargectl" "$(BUILD)/chargectl"
	@test -x "$(APP)/Contents/MacOS/ChargeGuardHelper" || { echo "error: helper not embedded in $(APP)/Contents/MacOS"; exit 1; }
	@test -x "$(APP)/Contents/MacOS/chargectl" || { echo "error: chargectl not embedded in $(APP)/Contents/MacOS"; exit 1; }
	@test -f "$(APP)/Contents/Library/LaunchDaemons/com.amir.chargeguard.helper.plist" || { echo "error: launchd plist not embedded in $(APP)/Contents/Library/LaunchDaemons"; exit 1; }
	codesign --verify --deep --strict --verbose=2 "$(APP)"
	@echo "Built and signed: $(APP) and $(BUILD)/chargectl"

test-core:
	cd Packages/ChargeGuardCore && swift test

test-system:
ifeq ($(UNAME),Darwin)
	cd Packages/ChargeGuardSystem && swift test
else
	@echo "Skipping ChargeGuardSystem tests: they need macOS (IOKit)."
endif

test: test-core test-system

run: build
	open "$(APP)"

run-sim: build
	open -n "$(APP)" --args --simulate

install-helper: build
	@echo "The fallback install copies the helper to /Library/PrivilegedHelperTools and loads it as a root"
	@echo "launchd daemon, so it runs with sudo and macOS asks for your password:"
	sudo /bin/bash scripts/install-helper.sh "$(CURDIR)/$(APP)"

# The script finds the app itself (the argument, /Applications/ChargeGuard.app, then build/ChargeGuard.app).
uninstall:
	@echo "Uninstalling restores normal charging first, then removes the root helper and its data, so it"
	@echo "runs with sudo and macOS asks for your password:"
	sudo /bin/bash scripts/uninstall.sh

dmg: build
	/bin/bash scripts/make-dmg.sh "$(APP)" "$(BUILD)/ChargeGuard.dmg"

clean:
	rm -rf "$(BUILD)" "$(PROJECT)"

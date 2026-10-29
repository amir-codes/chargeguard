# ChargeGuard build entry points (macOS only; Core tests also run on Linux/Windows with Swift).
#
#   make build           generate the Xcode project if needed, build Release into build/
#   make test            swift test for ChargeGuardCore and ChargeGuardSystem
#   make run             build and open build/ChargeGuard.app
#   make run-sim         build and open the app with --simulate (no helper, no SMC writes)
#   make install-helper  fallback helper install (asks for your password: sudo)
#   make uninstall       restore charging and remove the helper and data (sudo)
#   make dmg             build/ChargeGuard.dmg
#   make clean

PROJECT  := ChargeGuard.xcodeproj
SCHEME   := ChargeGuard
CONFIG   ?= Release
BUILD    := build
DERIVED  := $(BUILD)/DerivedData
PRODUCTS := $(DERIVED)/Build/Products/$(CONFIG)
APP      := $(BUILD)/ChargeGuard.app

# Apple Development certificate when one is in the keychain, otherwise ad-hoc ("-").
IDENTITY := $(or $(shell scripts/signing.sh identity 2>/dev/null),-)
TEAM     := $(shell scripts/signing.sh team 2>/dev/null)

.PHONY: all project build test test-core run run-sim install-helper uninstall dmg clean signing-info

all: build

$(PROJECT): project.yml
	xcodegen generate

project: $(PROJECT)

signing-info:
	@echo "Code signing identity: $(IDENTITY)"
	@echo "Team: $(if $(TEAM),$(TEAM),none (ad-hoc))"

build: $(PROJECT) signing-info
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(IDENTITY)" DEVELOPMENT_TEAM="$(TEAM)" \
		build
	rm -rf "$(APP)"
	ditto "$(PRODUCTS)/ChargeGuard.app" "$(APP)"
	ditto "$(PRODUCTS)/chargectl" "$(BUILD)/chargectl"
	@codesign --verify --deep --strict "$(APP)" && echo "Signature OK: $(APP)"

test-core:
	cd Packages/ChargeGuardCore && swift test

test: test-core
	cd Packages/ChargeGuardSystem && swift test

run: build
	open "$(APP)"

run-sim: build
	open -n "$(APP)" --args --simulate

install-helper: build
	@echo "Installing the root helper daemon needs your password (sudo):"
	sudo scripts/install-helper.sh "$(abspath $(APP))"

uninstall:
	@echo "Uninstalling restores normal charging and removes the root helper (sudo):"
	sudo scripts/uninstall.sh "$(abspath $(APP))"

dmg: build
	scripts/make-dmg.sh "$(APP)" "$(BUILD)/ChargeGuard.dmg"

clean:
	rm -rf "$(BUILD)" "$(PROJECT)"

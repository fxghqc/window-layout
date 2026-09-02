.PHONY: build test test-signing install uninstall clean

DEVELOPER_DIR ?= $(shell if [ -d /Applications/Xcode.app/Contents/Developer ]; then printf /Applications/Xcode.app/Contents/Developer; else xcode-select -p; fi)
export DEVELOPER_DIR

build:
	swift build

test:
	swift test

test-signing:
	./Tests/SigningIdentityIntegration.sh

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

clean:
	swift package clean

.PHONY: build test install uninstall clean

build:
	swift build

test:
	swift test

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

clean:
	swift package clean

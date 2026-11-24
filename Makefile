APP = build.noindex/Build/Products/Release/HandTracking.app

INSTALLED = $(HOME)/Applications/Hands.app
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: build test install run shortcuts stop clean

build:
	xcodegen generate -q
	xcodebuild -project HandTracking.xcodeproj -scheme HandTracking -configuration Release -derivedDataPath build.noindex -quiet build

test:
	swift test --disable-index-store

install: build stop
	mkdir -p $(HOME)/Applications
	rm -rf "$(INSTALLED)"
	ditto "$(APP)" "$(INSTALLED)"
	mkdir -p $(HOME)/.local/bin
	install -m 755 scripts/hands-remote $(HOME)/.local/bin/hands-remote
	-$(LSREGISTER) -u "$(CURDIR)/$(APP)"
	$(LSREGISTER) -f "$(INSTALLED)"

run: install
	open "$(INSTALLED)"

shortcuts:
	scripts/make-shortcuts

stop:
	-pkill -x HandTracking

clean:
	rm -rf build.noindex .build

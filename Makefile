PREFIX ?= $(HOME)/.local
VERSION ?= $(or $(shell git describe --tags --always --dirty 2>/dev/null | sed 's/^v//'),dev)
MACOS ?= 12.0

leftovers: src
	swiftc -O .build/main.swift -o leftovers

src:
	mkdir -p .build
	sed 's/^let VERSION = "dev"$$/let VERSION = "$(VERSION)"/' leftovers.swift > .build/main.swift

dist: src
	swiftc -O -target arm64-apple-macos$(MACOS) .build/main.swift -o .build/leftovers-arm64
	swiftc -O -target x86_64-apple-macos$(MACOS) .build/main.swift -o .build/leftovers-x86_64
	lipo -create .build/leftovers-arm64 .build/leftovers-x86_64 -output .build/leftovers
	mkdir -p dist
	tar -czf dist/leftovers-macos.tar.gz -C .build leftovers
	cd dist && shasum -a 256 leftovers-macos.tar.gz > leftovers-macos.tar.gz.sha256

install:
	@test -f leftovers || $(MAKE) leftovers
	install -d $(PREFIX)/bin
	install -m 755 leftovers $(PREFIX)/bin/leftovers

test:
	swiftc -D SELFTEST leftovers.swift -o /tmp/leftovers-selftest && /tmp/leftovers-selftest

clean:
	rm -rf leftovers .build dist

.PHONY: leftovers src dist install test clean

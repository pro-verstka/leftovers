PREFIX ?= $(HOME)/.local

leftovers: leftovers.swift
	swiftc -O leftovers.swift -o leftovers

install: leftovers
	install -d $(PREFIX)/bin
	install -m 755 leftovers $(PREFIX)/bin/leftovers

test:
	swiftc -D SELFTEST leftovers.swift -o /tmp/leftovers-selftest && /tmp/leftovers-selftest

clean:
	rm -f leftovers

.PHONY: install test clean

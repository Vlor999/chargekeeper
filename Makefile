VERSION := $(shell cat VERSION)
# Sparkle compares CFBundleVersion: 1.2.3 -> 10203
BUILD := $(shell awk -F. '{print $$1*10000+$$2*100+$$3}' VERSION)
XB = xcodebuild -project Jauge.xcodeproj -configuration Release -derivedDataPath build -quiet \
	MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD) $(XB_FLAGS)

all:
	xcodegen generate --quiet
	$(XB) -scheme Jauge build

check:
	mkdir -p build/check && cp Tests/LogicCheck.swift build/check/main.swift
	swiftc -swift-version 5 Shared/Model.swift Shared/Logic.swift build/check/main.swift -o build/check/logic && build/check/logic

clean:
	rm -rf build Jauge.xcodeproj

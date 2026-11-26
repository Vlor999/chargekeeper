VERSION := $(shell cat VERSION)
BUNDLE_VERSION := $(shell awk -F. '{print $$1*10000+$$2*100+$$3}' VERSION)
XB = xcodebuild -project ChargeKeeper.xcodeproj -configuration Release -derivedDataPath build -quiet \
	MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUNDLE_VERSION) $(XB_FLAGS)

all: project build

.PHONY: all project build check clean

build:
	$(XB) -scheme ChargeKeeper build

project:
	xcodegen generate --quiet
	xcodebuild -resolvePackageDependencies -project ChargeKeeper.xcodeproj -scheme ChargeKeeper -derivedDataPath build -quiet

check:
	mkdir -p build/check && cp Tests/LogicCheck.swift build/check/main.swift
	swiftc -swift-version 5 Shared/SharedConstants.swift Shared/Model.swift Shared/Logic.swift App/Strings.swift App/SettingsIndex.swift build/check/main.swift -o build/check/logic && build/check/logic

clean:
	rm -rf build ChargeKeeper.xcodeproj

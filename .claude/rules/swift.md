---
description: "Jauge Swift conventions: layout, concurrency, UI strings, native code."
paths:
  - "App/**"
  - "Daemon/**"
  - "Shared/**"
---

# Swift

- Swift 5 language mode (`project.yml`). Main-thread code; the service runs on the main run loop (timer, socket source, sleep notifications), no locks.
- `Shared/`: code used by both the app and the service (model, pure policy, socket client). No AppKit/SwiftUI/IOKit there.
- `Daemon/`: root service and CLI (`jaugectl`). C/ObjC for SMC and private PowerUI lives in `Native.m` behind `Native.h`.
- `App/`: SwiftUI. UI strings are English and go through `tr(...)`; add the French text to `App/Strings.swift` in the same change. Shortcuts strings go in `App/fr.lproj/Localizable.strings`.
- Comments only where the code can't say it (a hardware quirk, a SwiftUI workaround), in English.
- Deliberate shortcuts are marked `ponytail:` with their limit and upgrade path.

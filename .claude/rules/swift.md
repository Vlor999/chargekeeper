---
description: "ChargeKeeper Swift conventions: layout, concurrency, UI strings, native code."
paths:
  - "App/**"
  - "Daemon/**"
  - "Shared/**"
---

# Swift

- Swift 5 language mode (`project.yml`). Main-thread code; the service runs on the main run loop (timers, socket source, sleep and power source notifications), no locks.
- `Shared/`: code used by both the app and the service (model, pure policy, socket client). No AppKit/SwiftUI/IOKit there.
- `Daemon/`: root service and CLI (`chargekeeperctl`). C/ObjC for SMC and private PowerUI lives in `Native.m` behind `Native.h`.
- `App/`: SwiftUI. UI strings are English and go through `tr(...)`; add the French text to `App/Strings.swift` in the same change. Shortcuts strings go in `App/fr.lproj/Localizable.strings`.
- No comment explains code. Before writing one: rename, extract a named constant (constants module), a function, a type or an enum, or add a test. Units go in names (`capacityMAh`). No `///` restating the symbol, no `// MARK:`.
- Exception, only for a fact the code cannot express (hardware quirk, private API, OS or framework bug): one line, `// exception: <fact> (<source URL>)`, in English.
- One change does one thing. A shortcut taken, or a smell found that runs deeper than the task, is not fixed in the same PR: it gets its own issue and its own PR.
  - In the code: one line where it lives, `// ponytail: <the limit> (<issue URL>)`.
  - In the PR body: one line per issue, so the reviewer knows it is tracked.
- A `// ponytail:` line is tracked debt, not documentation. It is not fixed in passing: its own issue fixes it and removes the line.

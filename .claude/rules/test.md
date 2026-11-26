---
description: "ChargeKeeper tests: assert-based self-checks of the pure logic, run by make check."
paths:
  - "Shared/**"
  - "Tests/**"
---

# Tests

- Runner: `make check` compiles `Shared/SharedConstants.swift`, `Shared/Model.swift`, the pure logic files of `Shared/` (`Logic.swift`, `HealthSeries.swift`, `KeepAwake.swift`, `HistoryText.swift`, `Schedule.swift`, `PowerSamples.swift`, `Layout.swift`, `DiagnosticLog.swift`), `App/Strings.swift` (French table), `App/SettingsIndex.swift` (settings search) and `Tests/LogicCheck.swift` with `swiftc` and runs it. Plain `assert`, no XCTest.
- Test the pure logic in those `Shared/` files (charge policy, schedule, health series, power samples, log). A new pure logic file joins the `make check` list in the `Makefile`. Hardware (SMC, PowerUI, IOKit) and SwiftUI views are not unit tested: keep logic out of them so it stays testable.
- One function per behavior, named after the behavior; no comment.
- Every bug fixed in `Shared/` → an assertion that fails without the fix. New non-trivial logic (branch, loop, date math) → at least one assertion. No test for a one-liner.
- UI changes: verify with a rendered snapshot (`ImageRenderer`) or the local build, and measure CPU/memory with the menu closed.

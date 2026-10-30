---
description: "ChargeKeeper tests: assert-based self-checks of the pure logic, run by make check."
paths:
  - "Shared/**"
  - "Tests/**"
---

# Tests

- Runner: `make check` compiles `Shared/Model.swift`, `Shared/Logic.swift`, `App/Strings.swift` (French table) and `Tests/LogicCheck.swift` with `swiftc` and runs it. Plain `assert`, no XCTest.
- Test the pure logic in `Shared/Logic.swift` (charge policy, schedule). Hardware (SMC, PowerUI, IOKit) and SwiftUI views are not unit tested: keep logic out of them so it stays testable.
- One block per behavior, with a comment naming the behavior.
- Every bug fixed in `Shared/` → an assertion that fails without the fix. New non-trivial logic (branch, loop, date math) → at least one assertion. No test for a one-liner.
- UI changes: verify with a rendered snapshot (`ImageRenderer`) or the local build, and measure CPU/memory with the menu closed.

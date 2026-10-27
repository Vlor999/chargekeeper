// Logic self-check. Run: make check
import Foundation

func tick(_ c: Config, _ r: inout Runtime, _ pct: Int, ac: Bool = true, temp: Double? = nil, at t: TimeInterval = 0) -> Action {
    decide(c, &r, Inputs(percent: pct, adapter: ac, temperature: temp, now: Date(timeIntervalSince1970: t)))
}

var c = Config()
var r = Runtime()

// Limit: above limit holds at current level, below charges.
c.limit = 50
assert(tick(c, &r, 80) == .hold(at: 80) && r.state == .pause)
r = Runtime(); c.limit = 60
assert(tick(c, &r, 17) == .charge(to: 60) && r.state == .charging)
assert(tick(c, &r, 60) == .hold(at: 60))

// Discharge: down to limit then auto-off.
r = Runtime(); c.limit = 80; r.discharge = true
assert(tick(c, &r, 90) == .discharge && r.state == .discharging)
assert(tick(c, &r, 80) == .hold(at: 80) && !r.discharge)

// Auto discharge: drains without the manual toggle, then holds.
r = Runtime(); c.autoDischarge = true
assert(tick(c, &r, 90) == .discharge)
assert(tick(c, &r, 80) == .hold(at: 80))
c.autoDischarge = false

// Idle range: range 10, replug at 74 stays paused, at 62 charges to 80.
r = Runtime(); c.idle = true; c.idleRange = 10
_ = tick(c, &r, 80)
_ = tick(c, &r, 74, ac: false)
assert(tick(c, &r, 74) == .hold(at: 74) && r.state == .idle)
_ = tick(c, &r, 62, ac: false)
assert(tick(c, &r, 62) == .charge(to: 80))
assert(tick(c, &r, 75) == .charge(to: 80))
assert(tick(c, &r, 80) == .hold(at: 80))
c.idle = false

// Top-up: to 100, cleared on unplug.
r = Runtime(); r.topUp = true
assert(tick(c, &r, 85) == .charge(to: 100) && r.state == .topup)
_ = tick(c, &r, 100, ac: false)
assert(!r.topUp)

// Heat protection: block immediately, re-check after 5 min, then charge at least 5 min.
r = Runtime(); c.heatProtect = true; c.maxTemp = 35
assert(tick(c, &r, 45, temp: 36, at: 0) == .hold(at: 45) && r.state == .heatProtect)
assert(tick(c, &r, 45, temp: 30, at: 100) == .hold(at: 45))
assert(tick(c, &r, 45, temp: 30, at: 300) == .charge(to: 80))
assert(tick(c, &r, 46, temp: 40, at: 400) == .charge(to: 80))
assert(tick(c, &r, 46, temp: 40, at: 600) == .hold(at: 46))
c.heatProtect = false

// Calibration: 100 -> 10 -> 100 -> hold 1h -> back to limit.
r = Runtime(); r.calibration = .chargeFull
assert(tick(c, &r, 70) == .charge(to: 100))
_ = tick(c, &r, 100, at: 0); assert(r.calibration == .dischargeTo10)
assert(tick(c, &r, 50, at: 10) == .discharge)
_ = tick(c, &r, 10, at: 20); assert(r.calibration == .rechargeFull)
_ = tick(c, &r, 100, at: 30); assert(r.calibration == .hold)
assert(tick(c, &r, 100, at: 30 + 3599) == .hold(at: 100))
_ = tick(c, &r, 100, at: 30 + 3600); assert(r.calibration == .returnToLimit)
assert(tick(c, &r, 95, at: 4000) == .discharge)
assert(tick(c, &r, 80, at: 5000) == .hold(at: 80) && r.calibration == nil && r.state == .pause)

// LED.
c.led = .indicate; r = Runtime(); r.state = .pause
assert(ledColor(c, r, adapter: true, percent: 80) == .green)
r.state = .discharging; c.ledBlinkDischarge = true
assert(ledColor(c, r, adapter: true, percent: 90) == .orangeBlink)

// Schedule: monthly on the 31st skips 30-day months; weekdays skip weekends.
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
func d(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
var t = ScheduledTask(action: .calibrate, repeatRule: .monthly, start: d("2026-01-31T09:00:00Z"))
assert(lastOccurrence(t, after: d("2026-04-01T00:00:00Z"), upTo: d("2026-04-30T23:00:00Z"), calendar: cal) == nil)
assert(lastOccurrence(t, after: d("2026-05-01T00:00:00Z"), upTo: d("2026-05-31T10:00:00Z"), calendar: cal) == d("2026-05-31T09:00:00Z"))
t.repeatRule = .weekdays; t.start = d("2026-10-23T09:00:00Z")  // Friday
assert(lastOccurrence(t, after: d("2026-10-23T10:00:00Z"), upTo: d("2026-10-25T23:00:00Z"), calendar: cal) == nil)
assert(lastOccurrence(t, after: d("2026-10-23T10:00:00Z"), upTo: d("2026-10-26T09:30:00Z"), calendar: cal) == d("2026-10-26T09:00:00Z"))
t.repeatRule = .never
assert(lastOccurrence(t, after: d("2026-10-01T00:00:00Z"), upTo: d("2026-10-24T00:00:00Z"), calendar: cal) == d("2026-10-23T09:00:00Z"))

// Power flow: the MacBook gets the load minus the ports, unless the ports exceed the load.
assert(macWatts(system: 27, ports: [1, 13]) == 13)
assert(macWatts(system: 10, ports: [13]) == 10)

// Power flow labels: close centres are spread by gap and stay inside the height.
assert(spreadLabels([50, 51, 52], gap: 14, height: 200) == [50, 64, 78])
assert(spreadLabels([100, 108], gap: 14, height: 110) == [89, 103])

// Device icon: Apple devices by name, the rest generic.
assert(deviceIcon("iPhone") == "iphone" && deviceIcon("AirPods Charging Case") == "airpods" && deviceIcon(nil) == "cable.connector")

print("logic ok")

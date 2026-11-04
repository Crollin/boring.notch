// Auto-test du cycle Pomodoro.
// swiftc boringNotch/modules/Activities/FocusCycle.swift scripts/focus-selftest/main.swift -o "$TMPDIR/focus-selftest" && "$TMPDIR/focus-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

check(FocusCycle.next(after: .focus(round: 1), longEvery: 4) == .shortBreak(round: 1), "focus 1 -> courte")
check(FocusCycle.next(after: .shortBreak(round: 1), longEvery: 4) == .focus(round: 2), "courte 1 -> focus 2")
check(FocusCycle.next(after: .focus(round: 4), longEvery: 4) == .longBreak, "focus 4 -> longue")
check(FocusCycle.next(after: .longBreak, longEvery: 4) == .focus(round: 1), "longue -> focus 1")
check(FocusCycle.next(after: .focus(round: 1), longEvery: 1) == .longBreak, "longEvery 1")
check(FocusCycle.minutes(.shortBreak(round: 2), focus: 25, short: 5, long: 15) == 5, "minutes courte")
check(FocusCycle.minutes(.longBreak, focus: 25, short: 5, long: 15) == 15, "minutes longue")
check(FocusCycle.minutes(.focus(round: 3), focus: 25, short: 5, long: 15) == 25, "minutes focus")
print("OK")

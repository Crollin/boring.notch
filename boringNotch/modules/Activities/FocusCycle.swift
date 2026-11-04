//
//  FocusCycle.swift
//  boringNotch
//
//  Cycle Pomodoro pur (Foundation seulement) : focus → pause courte, pause longue tous les N focus.
//

import Foundation

enum FocusPhase: Equatable { case focus(round: Int), shortBreak(round: Int), longBreak }

enum FocusCycle {
    static func next(after p: FocusPhase, longEvery: Int) -> FocusPhase {
        switch p {
        case .focus(let r): r >= max(longEvery, 1) ? .longBreak : .shortBreak(round: r)
        case .shortBreak(let r): .focus(round: r + 1)
        case .longBreak: .focus(round: 1)
        }
    }

    static func minutes(_ p: FocusPhase, focus: Int, short: Int, long: Int) -> Int {
        switch p {
        case .focus: focus
        case .shortBreak: short
        case .longBreak: long
        }
    }
}

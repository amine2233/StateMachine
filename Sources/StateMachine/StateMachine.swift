//
//  StateMachine.swift
//  Swift 6 migration
//
import Foundation

// MARK: - State
open class State: Hashable, @unchecked Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
extension State: Equatable {
    public static func == (lhs: State, rhs: State) -> Bool { lhs.name == rhs.name }
}

// MARK: - Transition
open class Transition: Hashable, @unchecked Sendable {
    public let name: String
    public let from: State
    public let to: State
    public init(_ name: String, from: State, to: State) {
        self.name = name; self.from = from; self.to = to
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
extension Transition: Equatable {
    public static func == (lhs: Transition, rhs: Transition) -> Bool {
        lhs.name == rhs.name && lhs.from == rhs.from && lhs.to == rhs.to
    }
}

// MARK: - LifecycleEvent
public enum LifecycleEvent: Hashable, Sendable {
    case onState(_ state: State)
    case leaveState(_ state: State)
    case beforeTransition(_ transition: Transition)
    case onTransition(_ transition: Transition)
    case afterTransition(_ transition: Transition)
}
extension LifecycleEvent {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .onState(let s):           hasher.combine(0); hasher.combine(s)
        case .leaveState(let s):        hasher.combine(1); hasher.combine(s)
        case .beforeTransition(let t):  hasher.combine(2); hasher.combine(t)
        case .onTransition(let t):      hasher.combine(3); hasher.combine(t)
        case .afterTransition(let t):   hasher.combine(4); hasher.combine(t)
        }
    }
    public static func == (lhs: LifecycleEvent, rhs: LifecycleEvent) -> Bool {
        switch (lhs, rhs) {
        case (.onState(let a), .onState(let b)):                     return a == b
        case (.leaveState(let a), .leaveState(let b)):               return a == b
        case (.beforeTransition(let a), .beforeTransition(let b)):   return a == b
        case (.onTransition(let a), .onTransition(let b)):           return a == b
        case (.afterTransition(let a), .afterTransition(let b)):     return a == b
        default: return false
        }
    }
}

// MARK: - TransitionError
public enum TransitionError: Error, Sendable {
    case unknown
    case notAllowed
}

// MARK: - StateMachine
public actor StateMachine {
    private var currentState: State
    private var states: [State] = []
    private var transitions: [Transition] = []
    private var map: [State: [Transition]] = [:]
    private var contexts: [LifecycleEvent: @Sendable ([AnyHashable: Any]?) async -> Void] = [:]

    public init(initialState: State, transitions: [Transition]) {
        self.currentState = initialState
        for t in transitions { mapTransition(t) }
    }

    private func mapTransition(_ transition: Transition) {
        addState(transition.from); addState(transition.to); addTransition(transition)
        if var set = map[transition.from] { set.append(transition); map[transition.from] = set }
    }
    private func addState(_ state: State) {
        guard map[state] == nil else { return }
        states.append(state); map[state] = []
    }
    private func addTransition(_ transition: Transition) {
        guard !transitions.contains(transition) else { return }
        transitions.append(transition)
    }

    public func on(_ event: LifecycleEvent, using block: @escaping @Sendable ([AnyHashable: Any]?) async -> Void) {
        contexts[event] = block
    }

    public func fire(transition: Transition, userInfo: [AnyHashable: Any]?) async throws {
        guard transitions.contains(transition) else { throw TransitionError.unknown }
        guard canFire(transition: transition) else { throw TransitionError.notAllowed }
        await begin(transition)
        await execute(transition, userInfo: userInfo)
        await end(transition)
    }

    private func begin(_ transition: Transition) async {
        if let b = contexts[.beforeTransition(transition)] { await b(nil) }
        if let b = contexts[.leaveState(transition.from)] { await b(nil) }
    }
    private func execute(_ transition: Transition, userInfo: [AnyHashable: Any]?) async {
        currentState = transition.to
        if let b = contexts[.onState(transition.to)] { await b(userInfo) }
        if let b = contexts[.onTransition(transition)] { await b(userInfo) }
    }
    private func end(_ transition: Transition) async {
        if let b = contexts[.afterTransition(transition)] { await b(nil) }
    }

    public func isCurrent(state: State) -> Bool { state == currentState }
    public func canFire(transition: Transition) -> Bool { map[currentState]?.contains(transition) ?? false }
    public func allowedTransitions() -> [Transition]? { map[currentState] }
    public func state(name: String) -> State? { states.first { $0.name == name } }
    public func allStates() -> [State] { states }
    public func transition(name: String) -> Transition? { transitions.first { $0.name == name } }
    public func allTransitions() -> [Transition] { transitions }
}

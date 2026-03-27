//
//  StateMachine.swift
//  StateMachine
//
//  Created by Amine Bensalah on 30/09/2018.
//  Swift 6 improvements by opencloawben
//

// MARK: - State

/// A node in the state machine graph.
/// Subclass to add domain-specific behaviour; all stored properties must remain immutable
/// for the inherited `@unchecked Sendable` conformance to stay valid.
open class State: Hashable, @unchecked Sendable {

    /// Human-readable identifier for this state.
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    open func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(Self.self))
        hasher.combine(name)
    }
}

extension State: Equatable {
    public static func == (lhs: State, rhs: State) -> Bool {
        type(of: lhs) == type(of: rhs) && lhs.name == rhs.name
    }
}

// MARK: - Transition

/// A directed edge between two states.
/// Subclass to add domain-specific behaviour; all stored properties must remain immutable.
open class Transition: Hashable, @unchecked Sendable {

    /// Human-readable identifier for this transition.
    public let name: String
    /// The origin state.
    public let from: State
    /// The destination state.
    public let to: State

    public init(_ name: String, from: State, to: State) {
        self.name = name
        self.from = from
        self.to = to
    }

    open func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(Self.self))
        hasher.combine(name)
        hasher.combine(from)
        hasher.combine(to)
    }
}

extension Transition: Equatable {
    public static func == (lhs: Transition, rhs: Transition) -> Bool {
        type(of: lhs) == type(of: rhs)
            && lhs.name == rhs.name
            && lhs.from == rhs.from
            && lhs.to == rhs.to
    }
}

// MARK: - LifecycleEvent

/// Events emitted during a state machine transition.
public enum LifecycleEvent: Hashable, Sendable {
    /// The machine just entered this state.
    case onState(State)
    /// The machine is about to leave this state.
    case leaveState(State)
    /// Called before a transition fires.
    case beforeTransition(Transition)
    /// Called while a transition is executing (state already changed).
    case onTransition(Transition)
    /// Called after a transition completes.
    case afterTransition(Transition)

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
        case (.onState(let a),          .onState(let b)):          a == b
        case (.leaveState(let a),       .leaveState(let b)):       a == b
        case (.beforeTransition(let a), .beforeTransition(let b)): a == b
        case (.onTransition(let a),     .onTransition(let b)):     a == b
        case (.afterTransition(let a),  .afterTransition(let b)):  a == b
        default: false
        }
    }
}

// MARK: - TransitionError

/// Errors thrown by ``StateMachine/fire(transition:userInfo:)``.
public enum TransitionError: Error, Sendable, Equatable {
    /// The transition was not registered with this state machine.
    case unknown
    /// The transition is not valid from the current state.
    case notAllowed
}

// MARK: - StateMachine

/// An actor-based finite state machine.
///
/// All mutations and reads are serialised automatically by the actor —
/// no `DispatchQueue` juggling required.
///
/// Register observers with ``on(_:using:)`` (multiple observers per event
/// are supported) and fire transitions with ``fire(transition:userInfo:)``.
///
/// ## Example
/// ```swift
/// let idle    = State("idle")
/// let running = State("running")
/// let start   = Transition("start", from: idle, to: running)
///
/// let sm = StateMachine(initialState: idle, transitions: [start])
/// await sm.on(.onState(running)) { _ in print("Now running!") }
/// try await sm.fire(transition: start)
/// ```
public actor StateMachine {

    // MARK: Types

    /// Async, `Sendable` callback for lifecycle observers.
    public typealias Observer = @Sendable ([AnyHashable: Any]?) async -> Void

    // MARK: Private storage

    private var currentState: State
    private var states: [State] = []
    private var transitions: [Transition] = []
    /// Adjacency list: origin state -> allowed outgoing transitions.
    private var adjacency: [State: [Transition]] = [:]
    /// Multiple observers are supported per lifecycle event.
    private var observers: [LifecycleEvent: [Observer]] = [:]

    // MARK: Init

    /// Creates a state machine.
    /// - Parameters:
    ///   - initialState: The starting state (registered automatically).
    ///   - transitions:  All valid transitions (duplicates are silently ignored).
    public init(initialState: State, transitions: [Transition]) {
        self.currentState = initialState
        registerState(initialState)
        for t in transitions { register(t) }
    }

    // MARK: Registration

    private func registerState(_ state: State) {
        guard adjacency[state] == nil else { return }
        states.append(state)
        adjacency[state] = []
    }

    private func register(_ transition: Transition) {
        guard !transitions.contains(transition) else { return }
        registerState(transition.from)
        registerState(transition.to)
        transitions.append(transition)
        adjacency[transition.from, default: []].append(transition)
    }

    // MARK: Observers

    /// Adds an async observer for a lifecycle event.
    /// Multiple observers for the same event are called in registration order.
    public func on(_ event: LifecycleEvent, using block: @escaping Observer) {
        observers[event, default: []].append(block)
    }

    /// Removes all observers for a given lifecycle event.
    public func removeObservers(for event: LifecycleEvent) {
        observers[event] = nil
    }

    // MARK: Firing

    /// Attempts to fire a transition.
    ///
    /// Uses Swift 6 typed throws — callers catch `TransitionError` directly.
    ///
    /// - Parameters:
    ///   - transition: The transition to fire.
    ///   - userInfo:   Optional payload forwarded to observers (defaults to `nil`).
    /// - Throws: `TransitionError.unknown` if not registered;
    ///           `TransitionError.notAllowed` if not valid from the current state.
    public func fire(
        transition: Transition,
        userInfo: [AnyHashable: Any]? = nil
    ) async throws(TransitionError) {
        guard transitions.contains(transition) else { throw .unknown }
        guard canFire(transition: transition) else { throw .notAllowed }
        await notify(.beforeTransition(transition), userInfo: nil)
        await notify(.leaveState(transition.from), userInfo: nil)
        currentState = transition.to
        await notify(.onState(transition.to), userInfo: userInfo)
        await notify(.onTransition(transition), userInfo: userInfo)
        await notify(.afterTransition(transition), userInfo: nil)
    }

    private func notify(_ event: LifecycleEvent, userInfo: [AnyHashable: Any]?) async {
        guard let handlers = observers[event] else { return }
        for handler in handlers { await handler(userInfo) }
    }

    // MARK: Queries

    /// The current state.
    public var state: State { currentState }

    /// Returns `true` if the machine is currently in the given state.
    public func isCurrent(state: State) -> Bool { state == currentState }

    /// Returns `true` if the transition can be fired from the current state.
    public func canFire(transition: Transition) -> Bool {
        adjacency[currentState]?.contains(transition) ?? false
    }

    /// Returns the transitions valid from the current state (empty if none).
    public func allowedTransitions() -> [Transition] {
        adjacency[currentState] ?? []
    }

    /// Looks up a registered state by name.
    public func state(named name: String) -> State? {
        states.first { $0.name == name }
    }

    /// Returns all registered states.
    public func allStates() -> [State] { states }

    /// Looks up a registered transition by name.
    public func transition(named name: String) -> Transition? {
        transitions.first { $0.name == name }
    }

    /// Returns all registered transitions.
    public func allTransitions() -> [Transition] { transitions }
}

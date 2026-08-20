/// A named state of the machine.
public struct State: Hashable, Sendable {
    /// Name of the state.
    public let name: String

    /// Creates a state.
    ///
    ///     let state = State("Start")
    ///
    /// - Parameter name: The name of the state.
    public init(_ name: String) {
        self.name = name
    }
}

/// A named transition between two states.
public struct Transition: Hashable, Sendable {
    /// Name of the transition.
    public let name: String
    /// The origin state.
    public let from: State
    /// The destination state.
    public let to: State

    /// Creates a transition.
    ///
    ///     let transition = Transition("Start", from: State("Start"), to: State("Stop"))
    ///
    /// - Parameters:
    ///   - name: The name of the transition.
    ///   - from: The origin state.
    ///   - to: The destination state.
    public init(_ name: String, from: State, to: State) {
        self.name = name
        self.from = from
        self.to = to
    }
}

/// A point in the machine lifecycle an observer can subscribe to.
public enum LifecycleEvent: Hashable, Sendable {
    // State
    case onState(State)
    case leaveState(State)

    // Transition
    case beforeTransition(Transition)
    case onTransition(Transition)
    case afterTransition(Transition)
}

/// Errors thrown when firing a transition.
public enum TransitionError: Error, Sendable {
    /// The transition is not part of the machine.
    case unknown
    /// The transition cannot be fired from the current state.
    case notAllowed
}

/// A thread-safe finite state machine.
public actor StateMachine {
    /// Payload forwarded to the lifecycle observers.
    public typealias UserInfo = [String: any Sendable]

    /// An observer closure invoked on a lifecycle event.
    public typealias Observer = @Sendable (UserInfo?) async -> Void

    /// Every state reachable by the machine.
    public nonisolated let states: [State]

    /// Every transition known to the machine.
    public nonisolated let transitions: [Transition]

    /// The state the machine is currently in.
    public private(set) var currentState: State

    private let map: [State: [Transition]]
    private var observers: [LifecycleEvent: Observer] = [:]

    /// Creates a machine starting on `initialState`.
    ///
    /// - Parameters:
    ///   - initialState: The state the machine starts in.
    ///   - transitions: The transitions the machine accepts.
    public init(initialState: State, transitions: [Transition]) {
        self.currentState = initialState
        (self.states, self.transitions, self.map) = Self.build(transitions: transitions)
    }

    private static func build(
        transitions: [Transition]
    ) -> (states: [State], transitions: [Transition], map: [State: [Transition]]) {
        var states: [State] = []
        var knownTransitions: [Transition] = []
        var map: [State: [Transition]] = [:]

        for transition in transitions {
            for state in [transition.from, transition.to] where map[state] == nil {
                states.append(state)
                map[state] = []
            }

            guard !knownTransitions.contains(transition) else { continue }

            knownTransitions.append(transition)
            map[transition.from]?.append(transition)
        }

        return (states, knownTransitions, map)
    }

    // MARK: Transition

    /// Fires a transition and runs the matching lifecycle observers in order.
    ///
    /// - Parameters:
    ///   - transition: The transition to fire.
    ///   - userInfo: A payload forwarded to the `onState` and `onTransition` observers.
    /// - Throws: ``TransitionError/unknown`` when the transition is not part of the machine,
    ///   ``TransitionError/notAllowed`` when it cannot be fired from the current state.
    public func fire(transition: Transition, userInfo: UserInfo? = nil) async throws {
        guard transitions.contains(transition) else {
            throw TransitionError.unknown
        }
        guard canFire(transition: transition) else {
            throw TransitionError.notAllowed
        }

        await notify(.beforeTransition(transition))
        await notify(.leaveState(transition.from))

        currentState = transition.to

        await notify(.onState(transition.to), userInfo: userInfo)
        await notify(.onTransition(transition), userInfo: userInfo)
        await notify(.afterTransition(transition))
    }

    // MARK: Observer

    /// Registers an observer for a lifecycle event, replacing any previous one.
    ///
    /// - Parameters:
    ///   - event: The lifecycle event to observe.
    ///   - block: The closure invoked when the event happens.
    public func on(_ event: LifecycleEvent, using block: @escaping Observer) {
        observers[event] = block
    }

    private func notify(_ event: LifecycleEvent, userInfo: UserInfo? = nil) async {
        await observers[event]?(userInfo)
    }

    // MARK: Helpers

    /// The transitions that can be fired from the current state.
    public var allowedTransitions: [Transition] {
        map[currentState] ?? []
    }

    /// Returns whether `transition` can be fired from the current state.
    public func canFire(transition: Transition) -> Bool {
        allowedTransitions.contains(transition)
    }

    /// Returns the state named `name`, or `nil` when the machine has no such state.
    public nonisolated func state(name: String) -> State? {
        states.first { $0.name == name }
    }

    /// Returns the transition named `name`, or `nil` when the machine has no such transition.
    public nonisolated func transition(name: String) -> Transition? {
        transitions.first { $0.name == name }
    }
}

//
//  StateMachine.swift
//  StateMachine
//
//  Created by Amine Bensalah on 30/09/2018.
//

import Foundation
import Dispatch

/// State
open class State: Hashable {
    
    /// Name of state
    public let name: String
    
    /// StateMachine: Init State whit name
    ///
    ///     let state = State("Start")
    ///
    /// - Parameter name: The name of state
    /// - Returns: The new state
    public init(_ name: String) {
        self.name = name
    }

    /// hash Value
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// State Equatable
extension State: Equatable {
    
    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    static public func == (lhs: State, rhs: State) -> Bool {
        return lhs.name == rhs.name
    }
}

/// The Transition class
open class Transition: Hashable {
    
    /// Name of Transition
    public let name: String
    /// The begin state
    public let from: State
    /// The destination State
    public let to: State
    
    /// StateMachine: Init Transition whit name
    ///
    ///     let transition = Transition("Start", from: State("Start"), to: State("Stop"))
    ///
    /// - Parameter name:   The name of state
    /// - Parameter from:   The start state
    /// - Parameter to:     The destination state
    /// - Returns: The new state
    public init(_ name: String, from: State, to: State) {
        self.name = name
        self.from = from
        self.to = to
    }

    /// hash Value
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// Transition Equatable
extension Transition: Equatable {
    
    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    static public func == (lhs: Transition, rhs: Transition) -> Bool {
        return lhs.name == rhs.name && lhs.from == rhs.from && lhs.to == rhs.to
    }
}


public enum LifecycleEvent {
    
    // State
    case onState(_: State)
    case leaveState(_: State)
    
    // Transaition
    case beforeTransition(_: Transition)
    case onTransition(_: Transition)
    case afterTransition(_: Transition)
}

/// LifecycleEvent Hashable
extension LifecycleEvent: Hashable {

    /// hash Value
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .beforeTransition(let value):
            hasher.combine("bt\(value.hashValue)")
        case .leaveState(let value):
            hasher.combine("ls\(value.hashValue)")
        case .onState(let value):
            hasher.combine("os\(value.hashValue)")
        case .onTransition(let value):
            hasher.combine("ot\(value.hashValue)")
        case .afterTransition(let value):
            hasher.combine("at\(value.hashValue)")
        }
    }
}

/// LifecycleEvent Equatable
extension LifecycleEvent: Equatable {
    
    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (lhs: LifecycleEvent, rhs: LifecycleEvent) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}

/// Transition Error
public enum TransitionError: Error {
    
    case unknown
    case notAllowed
}

/// Context Struct
private struct Context {
    
    let queue: DispatchQueue
    var block: ([AnyHashable: Any]?) -> Void
}

open class StateMachine {
    private var currentState: State
    
    private let transitionQueue = DispatchQueue(label: "com.statemachine.transition",
                                                qos: .default,
                                                attributes: .concurrent,
                                                autoreleaseFrequency: .inherit,
                                                target: nil)
    
    private lazy var states: [State] = [State]()
    private lazy var transitions: [Transition] = [Transition]()
    private lazy var map: [State: [Transition]] = [State: [Transition]]()
    private lazy var contexts: [LifecycleEvent: Context] = [LifecycleEvent: Context]()
    
    public init(initialState: State,
                transitions: [Transition]) {
        
        self.currentState = initialState
        configure(transitions: transitions)
    }
    
    private func configure(transitions: [Transition]) {
        transitions.forEach { (transition) in
            map(transition: transition)
        }
    }
    
    private func map(transition: Transition) {
        add(state: transition.from)
        add(state: transition.to)
        add(transition: transition)
        
        if var set = map[transition.from] {
            set.append(transition)
            map[transition.from] = set
        }
    }
    
    private func add(state: State) {
        guard map[state] == nil else {
            return
        }
        
        states.append(state)
        map[state] = [Transition]()
    }
    
    private func add(transition: Transition) {
        guard !transitions.contains(transition) else {
            return
        }
        
        transitions.append(transition)
    }
    
    // MARK: Transition
    
    public func fire(transition: Transition,
                     userInfo: [AnyHashable: Any]?) throws {
        
        if !transitions.contains(transition) {
            throw TransitionError.unknown
        }
        
        if !canFire(transition: transition) {
            throw TransitionError.notAllowed
        }
        
        transitionQueue.async(flags: .barrier) { [weak self] in
            self?.begin(transition)
            self?.execute(transition,
                          userInfo: userInfo)
            self?.end(transition)
        }
    }
    
    // MARK: Observer
    
    public func on(_ event: LifecycleEvent,
                   queue: DispatchQueue = DispatchQueue.main,
                   using block: @escaping([AnyHashable: Any]?) -> Void) {
        
        let context = Context(queue: queue,
                              block: block)
        contexts[event] = context
    }
    
    // MARK: Lifecycle
    
    private func begin(_ transition: Transition) {
        if let context = contexts[.beforeTransition(transition)] {
            context.queue.async {
                context.block(nil)
            }
        }
        
        if let context = contexts[.leaveState(transition.from)] {
            context.queue.async {
                context.block(nil)
            }
        }
    }
    
    private func execute(_ transition: Transition,
                         userInfo: [AnyHashable: Any]?) {
        
        currentState = transition.to
        
        if let context = contexts[.onState(transition.to)] {
            context.queue.async {
                context.block(userInfo)
            }
        }
        
        if let context = contexts[.onTransition(transition)] {
            context.queue.async {
                context.block(userInfo)
            }
        }
    }
    
    private func end(_ transition: Transition) {
        if let context = contexts[.afterTransition(transition)] {
            context.queue.async {
                context.block(nil)
            }
        }
    }
    
    // MARK: Helpers
    
    public func isCurrent(state: State) -> Bool {
        var isCurrent = false
        
        transitionQueue.sync {
            isCurrent = (state == currentState)
        }
        
        return isCurrent
    }
    
    public func canFire(transition: Transition) -> Bool {
        guard let allowedTransition = allowedTransitions() else {
            return false
        }
        
        return !(allowedTransition.filter({
            $0 == transition
        }).isEmpty)
    }
    
    public func allowedTransitions() -> [Transition]? {
        var allowedTransition: [Transition]?
        
        transitionQueue.sync {
            allowedTransition = map[currentState]
        }
        
        return allowedTransition
    }
    
    public func state(name: String) -> State? {
        var state: State?
        
        transitionQueue.sync {
            state = states.first(where: {
                $0.name == name
            })
        }
        
        return state
    }
    
    public func allStates() -> [State] {
        var allStates = [State]()
        
        transitionQueue.sync {
            allStates = states
        }
        
        return allStates
    }
    
    public func transition(name: String) -> Transition? {
        var transition: Transition?
        
        transitionQueue.sync {
            transition = transitions.first(where: {
                $0.name == name
            })
        }
        
        return transition
    }
    
    public func allTransitions() -> [Transition] {
        var allTransitions = [Transition]()
        
        transitionQueue.sync {
            allTransitions = transitions
        }
        
        return allTransitions
    }
}

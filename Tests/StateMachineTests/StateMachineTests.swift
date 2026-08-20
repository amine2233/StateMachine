import Foundation
import XCTest
@testable import StateMachine

// MARK: Mocks
private enum Mocks {

    static let stateA = State("stateA")
    static let stateB = State("stateB")
    static let stateC = State("stateC")

    static let transitionA = Transition("transitionA", from: stateA, to: stateB)
    static let transitionB = Transition("transitionB", from: stateB, to: stateA)
    static let transitionC = Transition("transitionC", from: stateB, to: stateC)
    static let unknownTransition = Transition("unknown", from: stateB, to: stateA)

    static let transitions = [transitionA, transitionB]

    static let userInfo: StateMachine.UserInfo = ["key": "object"]

    static func machine() -> StateMachine {
        StateMachine(initialState: stateA, transitions: transitions)
    }
}

@Suite
struct StateMachineTests {

    @Test
    func allowedTransition() async throws {
        let stateMachine = Mocks.machine()

        try await stateMachine.fire(transition: Mocks.transitionA)

        #expect(await stateMachine.currentState == Mocks.stateB)
    }

    @Test
    func unknownTransition() async {
        let stateMachine = Mocks.machine()

        await #expect(throws: TransitionError.unknown) {
            try await stateMachine.fire(transition: Mocks.unknownTransition)
        }
    }

    @Test
    func notAllowedTransition() async {
        let stateMachine = Mocks.machine()

        await #expect(throws: TransitionError.notAllowed) {
            try await stateMachine.fire(transition: Mocks.transitionB)
        }
    }

    @Test
    func stateObserver() async throws {
        let stateMachine = Mocks.machine()

        try await confirmation("onState") { observed in
            await stateMachine.on(.onState(Mocks.stateB)) { _ in observed() }
            try await stateMachine.fire(transition: Mocks.transitionA)
        }
    }

    @Test
    func transitionObserver() async throws {
        let stateMachine = Mocks.machine()

        try await confirmation("onTransition") { observed in
            await stateMachine.on(.onTransition(Mocks.transitionA)) { _ in observed() }
            try await stateMachine.fire(transition: Mocks.transitionA)
        }
    }

    @Test
    func observerReceivesUserInfo() async throws {
        let stateMachine = Mocks.machine()

        try await confirmation("userInfo") { observed in
            await stateMachine.on(.onTransition(Mocks.transitionA)) { userInfo in
                #expect(userInfo?["key"] as? String == "object")
                observed()
            }
            try await stateMachine.fire(transition: Mocks.transitionA, userInfo: Mocks.userInfo)
        }
    }

    @Test
    func lifecycleRunsInOrder() async throws {
        let stateMachine = Mocks.machine()
        let recorder = Recorder()

        await stateMachine.on(.beforeTransition(Mocks.transitionA)) { _ in await recorder.record("before") }
        await stateMachine.on(.leaveState(Mocks.stateA)) { _ in await recorder.record("leave") }
        await stateMachine.on(.onState(Mocks.stateB)) { _ in await recorder.record("onState") }
        await stateMachine.on(.onTransition(Mocks.transitionA)) { _ in await recorder.record("onTransition") }
        await stateMachine.on(.afterTransition(Mocks.transitionA)) { _ in await recorder.record("after") }

        try await stateMachine.fire(transition: Mocks.transitionA)

        #expect(await recorder.events == ["before", "leave", "onState", "onTransition", "after"])
    }

    @Test
    func allowedTransitionsFollowCurrentState() async throws {
        let stateMachine = StateMachine(
            initialState: Mocks.stateA,
            transitions: [Mocks.transitionA, Mocks.transitionB, Mocks.transitionC]
        )

        #expect(await stateMachine.allowedTransitions == [Mocks.transitionA])

        try await stateMachine.fire(transition: Mocks.transitionA)

        #expect(await stateMachine.allowedTransitions == [Mocks.transitionB, Mocks.transitionC])
    }

    @Test
    func lookupByName() {
        let stateMachine = Mocks.machine()

        #expect(stateMachine.state(name: "stateB") == Mocks.stateB)
        #expect(stateMachine.state(name: "stateC") == nil)
        #expect(stateMachine.transition(name: "transitionA") == Mocks.transitionA)
        #expect(stateMachine.transition(name: "unknown") == nil)
    }
}

private actor Recorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

//
//  StateMachineTests.swift
//  StateMachine
//
//  Rewritten for Swift 6 async/await API.
//

import XCTest
@testable import StateMachine

// MARK: - Test Fixtures

private enum Fixture {
    // States
    static let idle    = State("idle")
    static let running = State("running")
    static let paused  = State("paused")
    static let stopped = State("stopped")

    // Transitions
    static let start   = Transition("start",   from: idle,    to: running)
    static let pause   = Transition("pause",   from: running, to: paused)
    static let resume  = Transition("resume",  from: paused,  to: running)
    static let stop    = Transition("stop",    from: running, to: stopped)
    static let unknown = Transition("unknown", from: idle,    to: stopped)

    static var basic: [Transition]  { [start, pause, resume, stop] }
    static var userInfo: [AnyHashable: Any] { ["key": "value"] }
}

// MARK: - Basic Transition Tests

final class TransitionTests: XCTestCase {

    // MARK: Allowed

    func testAllowedTransitionChangesState() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        try await sm.fire(transition: Fixture.start)
        let current = await sm.state
        XCTAssertEqual(current, Fixture.running)
    }

    func testMultipleSequentialTransitions() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        try await sm.fire(transition: Fixture.start)
        try await sm.fire(transition: Fixture.pause)
        try await sm.fire(transition: Fixture.resume)
        try await sm.fire(transition: Fixture.stop)
        let current = await sm.state
        XCTAssertEqual(current, Fixture.stopped)
    }

    // MARK: Errors

    func testUnknownTransitionThrows() async {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        do {
            try await sm.fire(transition: Fixture.unknown)
            XCTFail("Expected TransitionError.unknown")
        } catch TransitionError.unknown {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNotAllowedTransitionThrows() async {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        // pause is only valid from running, not from idle
        do {
            try await sm.fire(transition: Fixture.pause)
            XCTFail("Expected TransitionError.notAllowed")
        } catch TransitionError.notAllowed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: Helpers

    func testCanFireReflectsCurrentState() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        let canStart  = await sm.canFire(transition: Fixture.start)
        let canPause  = await sm.canFire(transition: Fixture.pause)
        XCTAssertTrue(canStart)
        XCTAssertFalse(canPause)
    }

    func testAllowedTransitionsFromInitialState() async {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        let allowed = await sm.allowedTransitions()
        XCTAssertEqual(allowed, [Fixture.start])
    }

    func testInitialStateIsRegisteredInAllStates() async {
        // Even a state with no outgoing transitions must appear in allStates()
        let sink = State("sink")
        let oneway = Transition("go", from: Fixture.idle, to: sink)
        let sm = StateMachine(initialState: Fixture.idle, transitions: [oneway])
        let all = await sm.allStates()
        XCTAssertTrue(all.contains(Fixture.idle))
        XCTAssertTrue(all.contains(sink))
    }

    func testStateNamedLookup() async {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        let found = await sm.state(named: "running")
        XCTAssertEqual(found, Fixture.running)
        let missing = await sm.state(named: "nonexistent")
        XCTAssertNil(missing)
    }

    func testTransitionNamedLookup() async {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        let found = await sm.transition(named: "start")
        XCTAssertEqual(found, Fixture.start)
    }
}

// MARK: - Observer Tests

final class ObserverTests: XCTestCase {

    func testOnStateObserverIsCalled() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var called = false
        await sm.on(.onState(Fixture.running)) { _ in called = true }
        try await sm.fire(transition: Fixture.start)
        XCTAssertTrue(called, "onState observer should have fired")
    }

    func testLeaveStateObserverIsCalled() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var called = false
        await sm.on(.leaveState(Fixture.idle)) { _ in called = true }
        try await sm.fire(transition: Fixture.start)
        XCTAssertTrue(called)
    }

    func testBeforeTransitionObserverIsCalled() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var stateAtCallback: State?
        // beforeTransition fires BEFORE the state changes
        await sm.on(.beforeTransition(Fixture.start)) { _ in
            Task { stateAtCallback = await sm.state }
        }
        try await sm.fire(transition: Fixture.start)
        // Give the nested Task a moment to run
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(stateAtCallback, Fixture.running, "State should already be running when beforeTransition fires (fire changes state before notifying)")
    }

    func testAfterTransitionObserverIsCalled() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var called = false
        await sm.on(.afterTransition(Fixture.start)) { _ in called = true }
        try await sm.fire(transition: Fixture.start)
        XCTAssertTrue(called)
    }

    func testUserInfoIsForwardedToOnStateObserver() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var received: [AnyHashable: Any]?
        await sm.on(.onState(Fixture.running)) { info in received = info }
        try await sm.fire(transition: Fixture.start, userInfo: Fixture.userInfo)
        let value = received?["key"] as? String
        XCTAssertEqual(value, "value")
    }

    func testUserInfoIsForwardedToOnTransitionObserver() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var received: [AnyHashable: Any]?
        await sm.on(.onTransition(Fixture.start)) { info in received = info }
        try await sm.fire(transition: Fixture.start, userInfo: Fixture.userInfo)
        let value = received?["key"] as? String
        XCTAssertEqual(value, "value")
    }

    // MARK: Multi-observer

    func testMultipleObserversForSameEventAreAllCalled() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var count = 0
        await sm.on(.onState(Fixture.running)) { _ in count += 1 }
        await sm.on(.onState(Fixture.running)) { _ in count += 1 }
        await sm.on(.onState(Fixture.running)) { _ in count += 1 }
        try await sm.fire(transition: Fixture.start)
        XCTAssertEqual(count, 3, "All 3 observers should fire")
    }

    func testMultipleObserversFireInRegistrationOrder() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var order: [Int] = []
        await sm.on(.onState(Fixture.running)) { _ in order.append(1) }
        await sm.on(.onState(Fixture.running)) { _ in order.append(2) }
        await sm.on(.onState(Fixture.running)) { _ in order.append(3) }
        try await sm.fire(transition: Fixture.start)
        XCTAssertEqual(order, [1, 2, 3])
    }

    func testRemoveObserversClearsAllForEvent() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var called = false
        await sm.on(.onState(Fixture.running)) { _ in called = true }
        await sm.removeObservers(for: .onState(Fixture.running))
        try await sm.fire(transition: Fixture.start)
        XCTAssertFalse(called, "Observer should not fire after removal")
    }
}

// MARK: - Concurrency Tests
// These tests validate that the actor serialises concurrent fire() calls
// and that no transition fires twice.

final class ConcurrencyTests: XCTestCase {

    /// Two concurrent fire(start) calls: only the first should succeed;
    /// the second must throw .notAllowed (state already changed).
    func testConcurrentFireDoesNotDoubleTransition() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)

        var errors: [TransitionError] = []
        var successCount = 0
        let lock = NSLock()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        try await sm.fire(transition: Fixture.start)
                        lock.withLock { successCount += 1 }
                    } catch let e as TransitionError {
                        lock.withLock { errors.append(e) }
                    } catch {}
                }
            }
        }

        // Exactly one fire() must succeed
        XCTAssertEqual(successCount, 1, "Exactly one concurrent fire should succeed")
        // The other must fail with .notAllowed (already in `running`)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first, .notAllowed)

        let current = await sm.state
        XCTAssertEqual(current, Fixture.running, "State should be running after one successful fire")
    }

    /// Flood with 10 concurrent fire(start) calls: exactly one wins.
    func testHighConcurrencyFireOnlySucceedsOnce() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    do {
                        try await sm.fire(transition: Fixture.start)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var out: [Bool] = []
            for await r in group { out.append(r) }
            return out
        }

        let wins = results.filter { $0 }.count
        XCTAssertEqual(wins, 1, "Only one of 10 concurrent fires should succeed")
    }

    /// Verifies that the state machine state is consistent after concurrent access:
    /// onState observer must only be called once.
    func testObserverCalledOnceAfterConcurrentFires() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)

        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()

        await sm.on(.onState(Fixture.running)) { _ in await counter.increment() }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try? await sm.fire(transition: Fixture.start)
                }
            }
        }

        let callCount = await counter.count
        XCTAssertEqual(callCount, 1, "onState(running) observer should fire exactly once")
    }

    /// Sequential fires on the same state machine complete in order.
    func testSequentialFiresCompleteInOrder() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)
        var visited: [State] = []
        for event in [LifecycleEvent.onState(Fixture.running),
                      .onState(Fixture.paused),
                      .onState(Fixture.stopped)] {
            if case .onState(let s) = event {
                let captured = s
                await sm.on(event) { _ in visited.append(captured) }
            }
        }

        try await sm.fire(transition: Fixture.start)   // idle -> running
        try await sm.fire(transition: Fixture.pause)   // running -> paused
        try await sm.fire(transition: Fixture.resume)  // paused -> running
        try await sm.fire(transition: Fixture.stop)    // running -> stopped

        XCTAssertEqual(visited, [Fixture.running, Fixture.paused, Fixture.running, Fixture.stopped])
    }

    /// After a failed concurrent fire, the state machine remains usable.
    func testStateMachineRemainsUsableAfterConcurrentFailure() async throws {
        let sm = StateMachine(initialState: Fixture.idle, transitions: Fixture.basic)

        // Concurrent fires: one wins
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask { try? await sm.fire(transition: Fixture.start) }
            }
        }

        // State machine should still work normally after concurrent failures
        let current = await sm.state
        XCTAssertEqual(current, Fixture.running)
        try await sm.fire(transition: Fixture.pause)
        let after = await sm.state
        XCTAssertEqual(after, Fixture.paused)
    }
}

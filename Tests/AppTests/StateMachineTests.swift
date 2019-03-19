//
//  StateMachine_iOSTests.swift
//  StateMachine iOSTests
//
//  Created by Amine Bensalah on 30/09/2018.
//

import XCTest
@testable import StateMachine

// MARK: Mocks
private struct StateMachineMocks {
    
    struct Constants {
        
        static let stateA = "stateA"
        static let stateB = "stateB"
        static let stateC = "stateC"
        
        static let transitionA = "transitionA"
        static let transitionB = "transitionB"
        static let transitionC = "transitionC"
    }
    
    static func stateA() -> State {
        return State(Constants.stateA)
    }
    
    static func stateB() -> State {
        return State(Constants.stateB)
    }
    
    static func stateC() -> State {
        return State(Constants.stateC)
    }
    
    static func transitionA() -> Transition {
        return Transition(Constants.transitionA,
                          from: stateA(),
                          to: stateB())
    }
    
    static func transitionB() -> Transition {
        return Transition(Constants.transitionB,
                          from: stateB(),
                          to: stateA())
    }
    
    static func transitionC() -> Transition {
        return Transition(Constants.transitionB,
                          from: stateB(),
                          to: stateC())
    }
    
    static func unknownTransition() -> Transition {
        return Transition("unknown",
                          from: stateB(),
                          to: stateA())
    }
    
    static func transitions() -> [Transition] {
        return [transitionA(), transitionB()]
    }
    
    static func userInfo() -> [AnyHashable: Any] {
        var userInfo = [AnyHashable: Any]()
        userInfo["key"] = "object"
        
        return userInfo
    }
}

class StateMachineTests: XCTestCase {

    func testAllowedTransition() {
        let transitions = StateMachineMocks.transitions()
        let stateMachine = StateMachine(initialState: StateMachineMocks.stateA(), transitions: transitions)
        let transition = StateMachineMocks.transitionA()
        
        XCTAssertNoThrow(try stateMachine.fire(transition: transition, userInfo: nil))
        
        let expectedState = StateMachineMocks.stateB()
        XCTAssertTrue(stateMachine.isCurrent(state: expectedState))
    }
    
    func testUnknownTransition() {
        let transitions = StateMachineMocks.transitions()
        let stateMachine = StateMachine(initialState: StateMachineMocks.stateA(),
                                        transitions: transitions)
        let transition = StateMachineMocks.unknownTransition()
        XCTAssertThrowsError(try stateMachine.fire(transition: transition, userInfo: nil)) { error in
            XCTAssertEqual(error as? TransitionError, TransitionError.unknown)
        }
    }
    
    func testNotAllowedTransition() {
        let transitions = StateMachineMocks.transitions()
        let stateMachine = StateMachine(initialState: StateMachineMocks.stateA(),
                                        transitions: transitions)
        
        let transition = StateMachineMocks.transitionB()
        
        XCTAssertThrowsError(try stateMachine.fire(transition: transition, userInfo: nil)) { error in
            XCTAssertEqual(error as? TransitionError, TransitionError.notAllowed)
        }
    }
    
    func testStateObserver() {
        let expectation = XCTestExpectation(description: "StateObserver")
        
        let transitions = StateMachineMocks.transitions()
        let stateMachine = StateMachine(initialState: StateMachineMocks.stateA(),
                                        transitions: transitions)
        let transition = StateMachineMocks.transitionA()
        
        stateMachine.on(.onState(StateMachineMocks.stateB())) { (_) in
            expectation.fulfill()
        }
        
        try? stateMachine.fire(transition: transition,
                               userInfo: nil)
        
        wait(for: [expectation],
             timeout: 1)
    }
    
    func testTransitionObserver() {
        let expectation = XCTestExpectation(description: "TransitionObserver")
        
        let transitions = StateMachineMocks.transitions()
        let stateMachine = StateMachine(initialState: StateMachineMocks.stateA(),
                                        transitions: transitions)
        let transition = StateMachineMocks.transitionA()
        
        stateMachine.on(.onTransition(transition)) { (_) in
            expectation.fulfill()
        }
        
        try? stateMachine.fire(transition: transition,
                               userInfo: nil)
        
        wait(for: [expectation],
             timeout: 1)
    }
    
    func testObserverWithUserInfo() {
        let transitions = StateMachineMocks.transitions()
        let stateMachine = StateMachine(initialState: StateMachineMocks.stateA(),
                                        transitions: transitions)
        let transition = StateMachineMocks.transitionA()
        let expectedUserInfo = StateMachineMocks.userInfo()
        
        stateMachine.on(.onTransition(StateMachineMocks.transitionB())) { (userInfo) in
            guard let userInfo = userInfo else {
                XCTFail("User Info must exists")
                return
            }
            
            XCTAssertTrue(NSDictionary(dictionary: userInfo).isEqual(to: expectedUserInfo))
        }
        
        try? stateMachine.fire(transition: transition,
                               userInfo: StateMachineMocks.userInfo())
    }
    
    func testStateMachineLifecycle() {
        let beforeTransitionExpectation = XCTestExpectation(description: "beforeTransitionExpectation")
        let leaveStateExpectation = XCTestExpectation(description: "leaveStateExpectation")
        let onStateExpectation = XCTestExpectation(description: "onStateExpectation")
        let onTransitionExpectation = XCTestExpectation(description: "onTransitionExpectation")
        
        let transitions = StateMachineMocks.transitions()
        let stateMachine = StateMachine(initialState: StateMachineMocks.stateA(),
                                        transitions: transitions)
        let transition = StateMachineMocks.transitionA()
        
        stateMachine.on(.beforeTransition(transition)) { (_) in
            beforeTransitionExpectation.fulfill()
        }
        
        stateMachine.on(.leaveState(StateMachineMocks.stateA())) { (_) in
            leaveStateExpectation.fulfill()
        }
        
        stateMachine.on(.onState(StateMachineMocks.stateB())) { (_) in
            onStateExpectation.fulfill()
        }
        
        stateMachine.on(.onTransition(transition)) { (_) in
            onTransitionExpectation.fulfill()
        }
        
        try? stateMachine.fire(transition: transition,
                               userInfo: nil)
        
        let expectations = [beforeTransitionExpectation, leaveStateExpectation, onStateExpectation, onTransitionExpectation]
        
        wait(for: expectations,
             timeout: 1,
             enforceOrder: true)
    }

    static let allTests = [
        ("testAllowedTransition",testAllowedTransition),
        ("testUnknownTransition",testUnknownTransition),
        ("testNotAllowedTransition",testNotAllowedTransition),
        ("testStateObserver",testStateObserver),
        ("testTransitionObserver",testTransitionObserver),
        ("testObserverWithUserInfo",testObserverWithUserInfo),
        ("testStateMachineLifecycle",testStateMachineLifecycle)
    ]
}

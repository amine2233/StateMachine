//
//  StateMachine_iOSTests.swift
//  StateMachine iOSTests
//
//  Created by Amine Bensalah on 30/09/2018.
//

import XCTest
@testable import StateMachine

class StateMachine_iOSTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() {
//        let state1 = State("State1")
//        let state2 = State("State2")
//
//        let transitionA = Transition("transitionA", from: state1, to: state2)
//        let transitionB = Transition("transitionB", from: state2, to: state1)
//
//        let stateMachine = StateMachine(initialState: state1, transitions: [transitionA, transitionB])
//
//        stateMachine.on(.onState(state2)) { (userInfo) in
//            print("onState \(state2.name)")
//        }
//
//        stateMachine.on(.leaveState(state1)) { (userInfo) in
//            print("leaveState \(state1.name)")
//        }
//
//        stateMachine.on(.beforeTransition(transitionA)) { (userInfo) in
//            print("beforeTransition \(transitionA.name)")
//        }
//
//        stateMachine.on(.onTransition(transitionA)) { (userInfo) in
//            print("onTransition \(transitionA.name)")
//        }
//
//        stateMachine.on(.afterTransition(transitionA)) { (userInfo) in
//            print("afterTransition \(transitionA.name)")
//        }
//
//        stateMachine.isCurrent(state: state1)
//        stateMachine.isCurrent(state: state2)
//        stateMachine.canFire(transition: transitionA)
//        stateMachine.canFire(transition: transitionB)
//
//        stateMachine.allowedTransitions()
//
//        do {
//            try stateMachine.fire(transition: transitionA, userInfo: nil)
//        } catch TransitionError.unknown {
//            print("Transition unknown")
//        } catch TransitionError.notAllowed {
//            print("Transition not allowed")
//        }
//
//        stateMachine.isCurrent(state: state2)
//
//        stateMachine.canFire(transition: transitionA)
//        stateMachine.canFire(transition: transitionB)
//
//        stateMachine.allowedTransitions()
//
//        stateMachine.state(name: "State2")
//        stateMachine.allStates()
//
//        stateMachine.transition(name: "transitionA")
//
//        stateMachine.allTransitions()
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}

#if os(Linux)

import XCTest
@testable import StateMachine

XCTMain([
    // StateMachineTests
    testCase(StateMachineTests.allTests),
    testCase(TaskQueue.allTests),
    testCase(Retry.allTests)
])

#endif

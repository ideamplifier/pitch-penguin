//
//  Pitch_PenguinTests.swift
//  Pitch PenguinTests
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

@testable import Pitch_Penguin
import XCTest

struct TuningNeedleMapper {
    func rotationDegrees(currentHz: Double, targetHz: Double, previousDegrees: Double, maxAngle: Double = 45.0) -> Double {
        guard currentHz > 0, targetHz > 0 else {
            return previousDegrees * 0.96
        }
        let cents = 1200.0 * log2(currentHz / targetHz)

        let displayRange = 50.0
        let clamped = max(-displayRange, min(displayRange, cents))
        let soft = tanh(clamped / 35.0)

        let target = soft * maxAngle
        let smoothed = 0.85 * previousDegrees + 0.15 * target
        return smoothed
    }
}

final class Pitch_PenguinTests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testTuningNeedleMapperPerformance() throws {
        let mapper = TuningNeedleMapper()
        var rotation: Double = 0
        let targetHz = 82.41

        measure {
            for i in 0 ... 1000 {
                let hz = 82.41 + Double(i) * 0.01
                rotation = mapper.rotationDegrees(currentHz: hz, targetHz: targetHz, previousDegrees: rotation)
            }
        }
    }
}

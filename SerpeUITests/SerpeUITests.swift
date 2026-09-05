//
//  SerpeUITests.swift
//  SerpeUITests
//
//  Empty on purpose. An AUv3's interface is hosted inside somebody else's app,
//  so the thing worth testing is not reachable from a UI test of the host app —
//  see TESTING.md, and the device sessions it describes.
//

import XCTest

final class SerpeUITests: XCTestCase {
    func testHostAppLaunches() throws {
        XCUIApplication().launch()
    }
}

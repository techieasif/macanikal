import XCTest
@testable import Macanikal

final class KeyMappingTests: XCTestCase {
    private var controller: AppController!

    override func setUp() {
        super.setUp()
        controller = AppController()
    }

    func testSpecialKeys() {
        XCTAssertEqual(controller.role(for: 49), .space)
        XCTAssertEqual(controller.role(for: 36), .enter)      // return
        XCTAssertEqual(controller.role(for: 76), .enter)      // keypad enter
        XCTAssertEqual(controller.role(for: 51), .backspace)  // delete
        XCTAssertEqual(controller.role(for: 117), .backspace) // forward delete
    }

    func testFunctionRowMapsToRow0() {
        XCTAssertEqual(controller.role(for: 53), .row(0))   // esc
        XCTAssertEqual(controller.role(for: 122), .row(0))  // F1
        XCTAssertEqual(controller.role(for: 111), .row(0))  // F12
    }

    func testNumberRowMapsToRow1() {
        XCTAssertEqual(controller.role(for: 18), .row(1))   // 1
        XCTAssertEqual(controller.role(for: 29), .row(1))   // 0
        XCTAssertEqual(controller.role(for: 50), .row(1))   // `
        XCTAssertEqual(controller.role(for: 24), .row(1))   // =
    }

    func testQwertyRowMapsToRow2() {
        XCTAssertEqual(controller.role(for: 48), .row(2))   // tab
        XCTAssertEqual(controller.role(for: 12), .row(2))   // Q
        XCTAssertEqual(controller.role(for: 35), .row(2))   // P
        XCTAssertEqual(controller.role(for: 42), .row(2))   // backslash
    }

    func testHomeRowMapsToRow3() {
        XCTAssertEqual(controller.role(for: 57), .row(3))   // caps lock
        XCTAssertEqual(controller.role(for: 0), .row(3))    // A
        XCTAssertEqual(controller.role(for: 37), .row(3))   // L
        XCTAssertEqual(controller.role(for: 39), .row(3))   // '
    }

    func testBottomRowsMapToRow4() {
        XCTAssertEqual(controller.role(for: 56), .row(4))   // left shift
        XCTAssertEqual(controller.role(for: 6), .row(4))    // Z
        XCTAssertEqual(controller.role(for: 44), .row(4))   // /
        XCTAssertEqual(controller.role(for: 55), .row(4))   // command
        XCTAssertEqual(controller.role(for: 63), .row(4))   // fn
        XCTAssertEqual(controller.role(for: 123), .row(4))  // left arrow
        XCTAssertEqual(controller.role(for: 126), .row(4))  // up arrow
    }

    func testUnknownKeyCodeFallsBackToHomeRow() {
        XCTAssertEqual(controller.role(for: 9999), .row(3))
        XCTAssertEqual(controller.role(for: -1), .row(3))
    }
}

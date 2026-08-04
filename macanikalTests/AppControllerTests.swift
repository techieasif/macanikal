import XCTest
@testable import Macanikal

final class AppControllerTests: XCTestCase {
    private var savedPack: String?

    override func setUp() {
        super.setUp()
        savedPack = UserDefaults.standard.string(forKey: "soundPack")
    }

    override func tearDown() {
        if let savedPack {
            UserDefaults.standard.set(savedPack, forKey: "soundPack")
        } else {
            UserDefaults.standard.removeObject(forKey: "soundPack")
        }
        super.tearDown()
    }

    func testInvalidStoredPackFallsBackToDefault() {
        UserDefaults.standard.set("no-such-pack", forKey: "soundPack")
        let controller = AppController()
        XCTAssertEqual(controller.packId, "mxbrown")
    }

    func testValidStoredPackIsRestored() {
        UserDefaults.standard.set("holypanda", forKey: "soundPack")
        let controller = AppController()
        XCTAssertEqual(controller.packId, "holypanda")
    }

    func testSelectingPackPersists() {
        let controller = AppController()
        controller.packId = "topre"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "soundPack"), "topre")
    }

    func testDefaultsAreRegistered() {
        let controller = AppController()
        XCTAssertGreaterThan(controller.volume, 0, "volume should default to an audible level")
        XCTAssertTrue((0...1).contains(controller.volume))
    }
}

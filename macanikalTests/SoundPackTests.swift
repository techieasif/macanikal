import XCTest
@testable import Macanikal

final class SoundPackTests: XCTestCase {
    func testCatalogHasThirteenPacks() {
        XCTAssertEqual(SoundPack.all.count, 13)
    }

    func testPackIDsAreUnique() {
        let ids = SoundPack.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate pack ids in catalog")
    }

    func testPackMetadataIsComplete() {
        for pack in SoundPack.all {
            XCTAssertFalse(pack.name.isEmpty, "\(pack.id) has no display name")
            XCTAssertTrue(["Clicky", "Tactile", "Linear", "Thocky"].contains(pack.style),
                          "\(pack.id) has unknown style \(pack.style)")
        }
    }

    /// Every pack must ship the samples the engine has no fallback for:
    /// all five row presses and the generic release. (Special-key samples are
    /// optional — the engine substitutes row samples when they're missing.)
    func testRequiredSamplesExistForEveryPack() {
        for pack in SoundPack.all {
            for row in 0..<5 {
                XCTAssertNotNil(
                    Bundle.main.url(forResource: "GENERIC_R\(row)", withExtension: "mp3",
                                    subdirectory: "Audio/\(pack.id)/press"),
                    "\(pack.id) is missing press/GENERIC_R\(row).mp3")
            }
            XCTAssertNotNil(
                Bundle.main.url(forResource: "GENERIC", withExtension: "mp3",
                                subdirectory: "Audio/\(pack.id)/release"),
                "\(pack.id) is missing release/GENERIC.mp3")
        }
    }

    func testDefaultPackExists() {
        XCTAssertTrue(SoundPack.all.contains { $0.id == "mxbrown" },
                      "the default pack must be in the catalog")
    }
}

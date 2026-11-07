import AppKit
import XCTest
@testable import AfterscreenSenderKit

final class BrightnessKeysTests: XCTestCase {
    func testRawSunKeysAreRecognizedAndDuplicateReportsDoNotDoubleStep() {
        XCTAssertEqual(BrightnessKeys.hidDirection(page: 7, usage: 58), -1)
        XCTAssertEqual(BrightnessKeys.hidDirection(page: 7, usage: 59), 1)
        XCTAssertEqual(BrightnessKeys.hidDirection(page: 12, usage: 0x6f), 1)
        XCTAssertNil(BrightnessKeys.hidDirection(page: 7, usage: 4))
        XCTAssertNil(BrightnessKeys.hidDirection(page: 12, usage: 0xe9))
        var held = Set<Int>()
        XCTAssertTrue(BrightnessKeys.transition(-1, down: true, held: &held))
        XCTAssertFalse(BrightnessKeys.transition(-1, down: true, held: &held))
        XCTAssertFalse(BrightnessKeys.transition(-1, down: false, held: &held))
        XCTAssertFalse(BrightnessKeys.transition(-1, down: false, held: &held))
        XCTAssertTrue(held.isEmpty)
        XCTAssertTrue(BrightnessKeys.transition(-1, down: true, held: &held))
    }
    func testDesktopFunctionKeysObservedOnMacMini() throws {
        let flags = NSEvent.ModifierFlags(rawValue: 8388864)
        let down = try XCTUnwrap(BrightnessKeys.functionAction(keyCode: 122, pressed: true, flags: flags))
        let up = try XCTUnwrap(BrightnessKeys.functionAction(keyCode: 120, pressed: true, flags: flags))
        XCTAssertEqual(BrightnessKeys.adjusted(0.5, action: down), 0.4375)
        XCTAssertEqual(BrightnessKeys.adjusted(0.5, action: up), 0.5625)
        XCTAssertFalse(try XCTUnwrap(BrightnessKeys.functionAction(keyCode: 122, pressed: false, flags: flags)).pressed)
        for code: Int64 in [0, 12, 53, 99, 103, 111] {
            XCTAssertNil(BrightnessKeys.functionAction(keyCode: code, pressed: true, flags: flags))
        }
        XCTAssertNil(BrightnessKeys.functionAction(keyCode: 122, pressed: true, flags: [.control, .function]))
        XCTAssertNil(BrightnessKeys.functionAction(keyCode: 120, pressed: true, flags: .command))
    }
    func testMediaKeyDownUpAndRepeat() throws {
        let up = try XCTUnwrap(BrightnessKeys.action(subtype: 8, data1: (2 << 16) | 0x0a00, flags: []))
        XCTAssertEqual(up.direction, 1)
        XCTAssertTrue(up.pressed)
        XCTAssertEqual(BrightnessKeys.adjusted(0.5, action: up), 0.5625)
        let release = try XCTUnwrap(BrightnessKeys.action(subtype: 8, data1: (2 << 16) | 0x0b00, flags: []))
        XCTAssertFalse(release.pressed)
        let repeatDown = try XCTUnwrap(BrightnessKeys.action(subtype: 8, data1: (3 << 16) | 0x0a01, flags: []))
        XCTAssertTrue(repeatDown.pressed)
        XCTAssertEqual(repeatDown.direction, -1)
    }
    func testDoesNotInterceptVolumeOrOtherSystemShortcuts() {
        for key in [0, 1, 7, 16, 17, 18] {
            XCTAssertNil(BrightnessKeys.action(subtype: 8, data1: (key << 16) | 0x0a00, flags: []))
        }
        XCTAssertNil(BrightnessKeys.action(subtype: 7, data1: (2 << 16) | 0x0a00, flags: []))
        XCTAssertNil(BrightnessKeys.action(subtype: 8, data1: (2 << 16) | 0x0c00, flags: []))
        XCTAssertNil(BrightnessKeys.action(subtype: 8, data1: (2 << 16) | 0x0a00, flags: .control))
        XCTAssertNil(BrightnessKeys.action(subtype: 8, data1: (2 << 16) | 0x0a00, flags: .command))
    }
    func testFineStepsAndClamping() throws {
        let fine = try XCTUnwrap(BrightnessKeys.action(subtype: 8, data1: (2 << 16) | 0x0a00, flags: [.option, .shift]))
        XCTAssertEqual(BrightnessKeys.adjusted(0.5, action: fine), 0.515625)
        XCTAssertEqual(BrightnessKeys.adjusted(0.999, action: fine), 1)
        let down = try XCTUnwrap(BrightnessKeys.action(subtype: 8, data1: (3 << 16) | 0x0a00, flags: []))
        XCTAssertEqual(BrightnessKeys.adjusted(0.01, action: down), 0)
    }
}

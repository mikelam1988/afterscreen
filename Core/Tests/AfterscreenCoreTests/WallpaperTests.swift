import XCTest
import AppKit
@testable import AfterscreenCore

final class WallpaperTests: XCTestCase {
    func testStaticPNGConvertedAndTransferRoundTrips() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        try png.write(to: file)
        let jpeg = try WallpaperImage.prepare(url: file)
        XCTAssertNoThrow(try WallpaperImage.validate(jpeg))
        let request = WallpaperTransfer(image: jpeg)
        let decoded = try JSONWire.decode(WallpaperTransfer.self, from: JSONWire.encode(request))
        XCTAssertEqual(decoded.id, request.id)
        XCTAssertEqual(decoded.image, jpeg)
        let success = WallpaperResult(id: request.id, error: nil)
        XCTAssertNil(try JSONWire.decode(WallpaperResult.self, from: JSONWire.encode(success)).error)
        let failure = WallpaperResult(id: request.id, error: "Cannot apply")
        XCTAssertEqual(try JSONWire.decode(WallpaperResult.self, from: JSONWire.encode(failure)).error, failure.error)
    }

    func testInvalidAndOversizedImagesRejected() {
        XCTAssertThrowsError(try WallpaperImage.validate(Data()))
        XCTAssertThrowsError(try WallpaperImage.validate(Data("not an image".utf8)))
        XCTAssertThrowsError(try WallpaperImage.validate(Data(repeating: 0, count: WallpaperImage.maxBytes + 1)))
        XCTAssertThrowsError(try WallpaperImage.prepare(url: URL(string: "https://example.com/wallpaper.jpg")!))
    }

    func testOlderReceiverDoesNotAdvertiseCapability() throws {
        let old = Welcome(protocolVersion: 1, name: "old", modelID: "", marketingName: "", osVersion: "",
                          gpuNames: [], panelPixels: PixelSize(width: 100, height: 100),
                          panelPoints: PixelSize(width: 100, height: 100), hevcDecode: false, h264Decode: true, bc7: false)
        let decoded = try JSONWire.decode(Welcome.self, from: JSONWire.encode(old))
        XCTAssertNil(decoded.wallpaperSync)
    }
}

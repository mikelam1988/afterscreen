import XCTest
@testable import AfterscreenCore

final class ConnectRequestTests: XCTestCase {
    let key = Data(repeating: 42, count: 32)
    let now = Date(timeIntervalSince1970: 1000)

    func testBonjourRoundTripAndIdentityBinding() throws {
        let request = ConnectRequest(senderID: "sender", receiverID: "receiver", key: key, now: now)
        let txt = NetService.dictionary(fromTXTRecord: NetService.data(fromTXTRecord: request.txt))
        let decoded = try XCTUnwrap(ConnectRequest(txt: txt))
        XCTAssertEqual(request, decoded)
        XCTAssertTrue(decoded.verifies(senderID: "sender", receiverID: "receiver", key: key, now: now))
        XCTAssertFalse(decoded.verifies(senderID: "other", receiverID: "receiver", key: key, now: now))
        XCTAssertFalse(decoded.verifies(senderID: "sender", receiverID: "other", key: key, now: now))
        XCTAssertFalse(decoded.verifies(senderID: "sender", receiverID: "receiver", key: Data(repeating: 1, count: 32), now: now))
    }

    func testUnpairedRequestUsesOnlyLastReceiverOnDirectCable() throws {
        let request = ConnectRequest(senderID: "*", receiverID: "receiver", key: nil, now: now)
        let decoded = try XCTUnwrap(ConnectRequest(txt: NetService.dictionary(fromTXTRecord: NetService.data(fromTXTRecord: request.txt))))
        XCTAssertEqual(decoded.cableLink(senderID: "sender", isLastReceiver: true, links: [.wifi, .thunderbolt], now: now), .thunderbolt)
        XCTAssertEqual(decoded.cableLink(senderID: "sender", isLastReceiver: true, links: [.usb], now: now), .usb)
        XCTAssertNil(decoded.cableLink(senderID: "sender", isLastReceiver: true, links: [.wifi, .ethernet], now: now))
        XCTAssertNil(decoded.cableLink(senderID: "sender", isLastReceiver: false, links: [.thunderbolt], now: now))
        XCTAssertNil(decoded.cableLink(senderID: "sender", isLastReceiver: true, links: [.thunderbolt], now: now.addingTimeInterval(121)))
        XCTAssertFalse(decoded.verifies(senderID: "sender", receiverID: "receiver", key: key, now: now))
        let targeted = ConnectRequest(senderID: "other", receiverID: "receiver", key: nil, now: now)
        XCTAssertNil(targeted.cableLink(senderID: "sender", isLastReceiver: true, links: [.usb], now: now))
        let signed = ConnectRequest(senderID: "sender", receiverID: "receiver", key: key, now: now)
        XCTAssertNil(signed.cableLink(senderID: "sender", isLastReceiver: true, links: [.usb], now: now))
    }

    func testExpiredFutureAndTamperedRequestsAreRejected() throws {
        let request = ConnectRequest(senderID: "sender", receiverID: "receiver", key: key, now: now)
        for offset: TimeInterval in [121, -31] {
            XCTAssertFalse(request.verifies(senderID: "sender", receiverID: "receiver", key: key, now: now.addingTimeInterval(offset)))
        }
        var txt = request.txt
        txt["connect-time"] = Data("1001".utf8)
        XCTAssertFalse(try XCTUnwrap(ConnectRequest(txt: txt)).verifies(senderID: "sender", receiverID: "receiver", key: key, now: now))
        txt["connect-nonce"] = Data()
        XCTAssertNil(ConnectRequest(txt: txt))
        XCTAssertNil(ConnectRequest(txt: [:]))
    }
}

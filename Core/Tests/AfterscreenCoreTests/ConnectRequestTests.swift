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

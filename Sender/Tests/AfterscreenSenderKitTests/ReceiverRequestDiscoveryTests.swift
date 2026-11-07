import XCTest
import AfterscreenCore
@testable import AfterscreenSenderKit

final class ReceiverRequestDiscoveryTests: XCTestCase {
    func testTXTChangeDeliversRequestWithoutRemovingReceiver() {
        let discovery = Discovery()
        let service = NetService(domain: "local.", type: "_afterscreen._tcp.", name: "iMac", port: 12345)
        var lists: [[DiscoveredReceiver]] = []
        discovery.onChange = { lists.append($0) }
        let initial = ["id": Data("receiver".utf8)]
        discovery.netService(service, didUpdateTXTRecord: NetService.data(fromTXTRecord: initial))
        let request = ConnectRequest(senderID: "sender", receiverID: "receiver", key: Data(repeating: 42, count: 32))
        let updated = NetService.data(fromTXTRecord: initial.merging(request.txt) { _, new in new })
        discovery.netService(service, didUpdateTXTRecord: updated)
        discovery.netService(service, didUpdateTXTRecord: updated)
        XCTAssertEqual(lists.count, 2)
        XCTAssertEqual(lists.last?.first?.connectRequest, request)
        XCTAssertFalse(AppModel.listsNewEndpoint(old: lists[0], new: lists[1]))
        discovery.netService(service, didUpdateTXTRecord: NetService.data(fromTXTRecord: initial))
        XCTAssertNil(lists.last?.first?.connectRequest)
    }
}

import Foundation
import CryptoKit

/// A short-lived, paired receiver request carried by its existing Bonjour TXT record.
public struct ConnectRequest: Equatable {
    public let senderID: String
    public let nonce: Data
    public let issued: String
    public let proof: Data

    public init(senderID: String, receiverID: String, key: Data?, now: Date = Date()) {
        self.senderID = senderID
        nonce = Pairing.nonce()
        issued = String(Int64(now.timeIntervalSince1970))
        if let key = key {
            proof = Self.sign(senderID: senderID, receiverID: receiverID, nonce: nonce, issued: issued, key: key)
        } else { proof = Data() }
    }

    public init?(txt: [String: Data]) {
        guard let target = txt["connect-to"], let sender = String(data: target, encoding: .utf8), !sender.isEmpty,
              let nonce = txt["connect-nonce"], nonce.count == 16,
              let time = txt["connect-time"], let issued = String(data: time, encoding: .utf8), Int64(issued) != nil else { return nil }
        let proof = txt["connect-proof"] ?? Data()
        guard proof.isEmpty || proof.count == 32 else { return nil }
        senderID = sender; self.nonce = nonce; self.issued = issued; self.proof = proof
    }

    public var txt: [String: Data] {
        var values = ["connect-to": Data(senderID.utf8), "connect-nonce": nonce, "connect-time": Data(issued.utf8)]
        if !proof.isEmpty { values["connect-proof"] = proof }
        return values
    }

    public func verifies(senderID: String, receiverID: String, key: Data, now: Date = Date()) -> Bool {
        guard self.senderID == senderID, isCurrent(now) else { return false }
        return Pairing.matches(proof, Self.sign(senderID: senderID, receiverID: receiverID, nonce: nonce, issued: issued, key: key))
    }

    private func isCurrent(_ now: Date) -> Bool {
        guard let time = TimeInterval(issued) else { return false }
        return now.timeIntervalSince1970 - time >= -30 && now.timeIntervalSince1970 - time <= 120
    }

    /// A request without a key is only a hint to the last receiver over a direct cable.
    /// Never fall back from a bad signature, or send an unpaired request over LAN/Wi-Fi.
    public func cableLink(senderID: String, isLastReceiver: Bool, links: [LinkKind], now: Date = Date()) -> LinkKind? {
        guard proof.isEmpty, isCurrent(now), isLastReceiver,
              self.senderID == senderID || self.senderID == "*" else { return nil }
        return links.first { $0 == .thunderbolt || $0 == .usb }
    }

    private static func sign(senderID: String, receiverID: String, nonce: Data, issued: String, key: Data) -> Data {
        let transcript = Pairing.Transcript(senderID: senderID, receiverID: receiverID,
                                           senderNonce: nonce, receiverNonce: Data(issued.utf8))
        return Data(HMAC<SHA256>.authenticationCode(for: Data("afterscreen-connect-request-v1".utf8) + transcript.bytes,
                                                  using: SymmetricKey(data: key)))
    }
}

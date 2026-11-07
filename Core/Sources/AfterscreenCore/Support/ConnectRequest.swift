import Foundation
import CryptoKit

/// A short-lived, paired receiver request carried by its existing Bonjour TXT record.
public struct ConnectRequest: Equatable {
    public let senderID: String
    public let nonce: Data
    public let issued: String
    public let proof: Data

    public init(senderID: String, receiverID: String, key: Data, now: Date = Date()) {
        self.senderID = senderID
        nonce = Pairing.nonce()
        issued = String(Int64(now.timeIntervalSince1970))
        proof = Self.sign(senderID: senderID, receiverID: receiverID, nonce: nonce, issued: issued, key: key)
    }

    public init?(txt: [String: Data]) {
        guard let target = txt["connect-to"], let sender = String(data: target, encoding: .utf8), !sender.isEmpty,
              let nonce = txt["connect-nonce"], nonce.count == 16,
              let time = txt["connect-time"], let issued = String(data: time, encoding: .utf8), Int64(issued) != nil,
              let proof = txt["connect-proof"], proof.count == 32 else { return nil }
        senderID = sender; self.nonce = nonce; self.issued = issued; self.proof = proof
    }

    public var txt: [String: Data] {
        ["connect-to": Data(senderID.utf8), "connect-nonce": nonce,
         "connect-time": Data(issued.utf8), "connect-proof": proof]
    }

    public func verifies(senderID: String, receiverID: String, key: Data, now: Date = Date()) -> Bool {
        guard self.senderID == senderID, let time = TimeInterval(issued),
              now.timeIntervalSince1970 - time >= -30, now.timeIntervalSince1970 - time <= 120 else { return false }
        return Pairing.matches(proof, Self.sign(senderID: senderID, receiverID: receiverID, nonce: nonce, issued: issued, key: key))
    }

    private static func sign(senderID: String, receiverID: String, nonce: Data, issued: String, key: Data) -> Data {
        let transcript = Pairing.Transcript(senderID: senderID, receiverID: receiverID,
                                           senderNonce: nonce, receiverNonce: Data(issued.utf8))
        return Data(HMAC<SHA256>.authenticationCode(for: Data("afterscreen-connect-request-v1".utf8) + transcript.bytes,
                                                  using: SymmetricKey(data: key)))
    }
}

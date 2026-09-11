import CryptoKit
import Foundation

/// A private local unlock for the app's own developer, entirely separate
/// from real Polar.sh licensing. Pasting the matching secret token into the
/// License field in Settings unlocks Pro instantly with no network call —
/// it is never validated against Polar, never distributed to customers.
///
/// This repo is public, so only the SHA-256 hash of that token lives here,
/// never the token itself — the plaintext is kept outside version control.
/// A hash match doesn't weaken real customer licensing at all: once the
/// Polar org is live, customers still go through `LicenseChecker.verify`
/// exactly as before; this is purely a second, narrower door that only
/// opens for whoever already has the one string that hashes to this value.
enum OwnerAccess {
    private static let overrideKeyHash =
        "47b7fc7a57d56f18abfaffa149970d3f8b4675270d133ee83c4a780cea8f3d70"

    static func isOwnerKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex == overrideKeyHash
    }
}

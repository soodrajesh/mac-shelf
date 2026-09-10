import Foundation
import CryptoKit
import Security

/// MacShelf Pro licensing.
///
/// Structurally a port of mac-cleanup's `Sources/MacGroomLicenseCheck.swift`
/// (MacGroom's actual, currently-shipping implementation — Polar.sh's
/// customer-portal License Keys API, not the older Lemon Squeezy shape
/// `macgroom-license-check/INTEGRATION.md` still describes, which is stale).
/// Same verification flow, same tamper-evident Keychain cache, same error
/// taxonomy — pointed at a **separate** MacShelf Pro product in Polar, per
/// app licensing rather than a Suite Pro bundle.
///
/// ---
/// ## TODO before this can go live
///
/// `PolarConfig.organizationId` below is a placeholder. Until the real
/// MacShelf Pro product/license-key benefit exists in the Polar dashboard:
/// - Every `verify()` call will 404 against Polar (mapped to
///   `.invalidLicenseKey`) — the app fails closed to the free tier, it does
///   not crash.
/// - Fill in `organizationId` once the product exists (Polar → Organization
///   Settings → copy the Organization ID — same place MacGroom's was taken
///   from), or set the `MACSHELF_POLAR_ORG_ID` environment variable to
///   override it without a rebuild (e.g. for a TestFlight-style dry run).
enum PolarConfig {
    // TODO(polar-setup): Create the "MacShelf Pro" product + license-key
    // benefit in the Polar dashboard (separate from MacGroom's product —
    // this is per-app licensing, not a bundle), then replace this
    // placeholder with the real Organization ID.
    private static let placeholderOrganizationId = "TODO_POLAR_ORGANIZATION_ID"

    static var organizationId: String {
        ProcessInfo.processInfo.environment["MACSHELF_POLAR_ORG_ID"] ?? placeholderOrganizationId
    }

    /// `false` until `MACSHELF_POLAR_ORG_ID` is set or the placeholder above
    /// is replaced with a real Polar Organization ID. `LicenseChecker.verify`
    /// checks this *before* calling Polar, so a not-yet-configured backend
    /// fails with a distinct "not available yet" message instead of ever
    /// reaching the API and coming back as a false "invalid key" (see
    /// UX-AUDIT.md finding P-1).
    static var isConfigured: Bool {
        organizationId != placeholderOrganizationId
    }

    /// TODO(polar-setup): once the product exists, fill in its real
    /// checkout link (Polar → Products → MacShelf Pro → Share → copy
    /// checkout link) so `LicenseManagementView`'s "Buy MacShelf Pro" button
    /// goes somewhere real instead of the gogenops.com product page.
    static var checkoutURL: URL? {
        URL(string: ProcessInfo.processInfo.environment["MACSHELF_POLAR_CHECKOUT_URL"]
            ?? "https://gogenops.com/mac-apps/macshelf/")
    }
}

/// Local, tamper-evident cache for verified license state. Keychain instead
/// of `UserDefaults` (not writable via `defaults`/plutil without Keychain
/// Services), plus an HMAC-SHA256 tag over the cached payload so a forged
/// entry written by any other means fails the tag check on read and forces
/// a real network re-verification. Ported as-is from MacGroom's
/// `SecureLicenseCache` — same reasoning, same honest limit (raises the bar
/// from "one shell command" to "extract the embedded key from the compiled
/// binary"; nothing purely client-side can close that last gap).
private enum SecureLicenseCache {
    private static let licenseService = "com.rajeshsood.macshelf.license.cache.v1"

    /// Byte-masked so the secret isn't plain text in the binary's strings
    /// table. This is MacShelf's own key, distinct from MacGroom's —
    /// generate a fresh random 25-byte value before shipping rather than
    /// reusing this placeholder.
    // TODO(polar-setup): rotate this to a freshly generated random value
    // before first Pro release, same as MacGroom's rotation note.
    private static var hmacKey: SymmetricKey {
        let masked: [UInt8] = [
            0x7a, 0x12, 0xf0, 0x88, 0x3d, 0x64, 0xab, 0x59, 0xe2, 0x0c,
            0x91, 0x3e, 0x77, 0xd4, 0x2a, 0x56, 0xc8, 0x0f, 0x19, 0x8b,
            0x4d, 0xa1, 0x6e, 0xf3, 0x22
        ]
        let bytes = masked.enumerated().map { i, b in b ^ UInt8((i * 5 + 23) & 0xFF) }
        return SymmetricKey(data: Data(bytes))
    }

    private struct SignedPayload: Codable {
        let payload: Data
        let tag: Data
    }

    private struct CachedEnvelope: Codable {
        let cachedAt: Date
        let license: License
    }

    private static func computeTag(_ payload: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: payload, using: hmacKey))
    }

    static func readLicense(_ licenseKey: String) -> (Date, License)? {
        guard let data = keychainRead(service: licenseService, account: licenseKey) else { return nil }
        guard let signed = try? JSONDecoder().decode(SignedPayload.self, from: data) else { return nil }
        guard computeTag(signed.payload) == signed.tag else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(CachedEnvelope.self, from: signed.payload) else { return nil }
        return (envelope.cachedAt, envelope.license)
    }

    static func writeLicense(_ licenseKey: String, _ license: License) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(CachedEnvelope(cachedAt: Date(), license: license)) else { return }
        let signed = SignedPayload(payload: payload, tag: computeTag(payload))
        guard let signedData = try? JSONEncoder().encode(signed) else { return }
        keychainWrite(service: licenseService, account: licenseKey, data: signedData)
    }

    static func clearLicense(_ licenseKey: String) {
        keychainDelete(service: licenseService, account: licenseKey)
    }

    static func clearAll() {
        keychainDeleteAll(service: licenseService)
    }

    // MARK: - Keychain primitives

    private static func keychainRead(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func keychainWrite(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        // `AfterFirstUnlock`, not `WhenUnlocked` — this is a menu-bar /
        // background-launchable app; a license check firing before the
        // user unlocks their session shouldn't hard-fail.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func keychainDelete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func keychainDeleteAll(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Process-wide serialization for `LicenseChecker.verify()` calls, keyed by
/// license key — the main popover and an independent Settings window can
/// both hold a `LicenseChecker` at once.
private final class VerifyLock: @unchecked Sendable {
    static let shared = VerifyLock()

    private let lock = NSLock()
    private var inFlight: [String: Task<License, Error>] = [:]

    func run(key: String, _ operation: @escaping () async throws -> License) async throws -> License {
        let (task, isNew) = getOrCreate(key: key, operation: operation)
        defer { if isNew { clear(key) } }
        return try await task.value
    }

    private func getOrCreate(
        key: String,
        operation: @escaping () async throws -> License
    ) -> (task: Task<License, Error>, isNew: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inFlight[key] {
            return (existing, false)
        }
        let task = Task { try await operation() }
        inFlight[key] = task
        return (task, true)
    }

    private func clear(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        inFlight[key] = nil
    }
}

/// Error types for license verification — same taxonomy as MacGroom's, kept
/// unified across the mac-apps line so any future shared support tooling
/// can key off the same case names.
public enum LicenseCheckError: LocalizedError {
    case invalidLicenseKey
    case networkError(URLError)
    case invalidResponse
    case licenseExpired
    case licenseDisabled
    case activationLimitExceeded
    case activationFailed(String)
    case codingError(Error)
    case unknown(String)
    case wrongProduct
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MacShelf Pro isn't available for purchase yet — check back soon."
        case .invalidLicenseKey:
            return "The license key is invalid or not recognized."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the license server."
        case .licenseExpired:
            return "This license has expired."
        case .licenseDisabled:
            return "This license has been disabled."
        case .activationLimitExceeded:
            return "This license has reached its activation limit."
        case .activationFailed(let message):
            return "Activation failed: \(message)"
        case .codingError(let error):
            return "Error processing license data: \(error.localizedDescription)"
        case .unknown(let message):
            return message
        case .wrongProduct:
            return "This license key isn't valid for MacShelf."
        }
    }
}

/// Represents a verified license. `instanceId` stays nil under the Polar
/// integration unless per-device activation limits are ever turned on for
/// the MacShelf Pro benefit — kept on the struct for source parity with
/// MacGroom's rather than removed.
public struct License: Codable, Equatable {
    public let key: String
    public let isValid: Bool
    public let status: String?
    public let expiresAt: Date?
    public let activationLimit: Int?
    public let activationUsage: Int?
    public let instanceId: String?

    public init(
        key: String,
        isValid: Bool,
        status: String? = nil,
        expiresAt: Date? = nil,
        activationLimit: Int? = nil,
        activationUsage: Int? = nil,
        instanceId: String? = nil
    ) {
        self.key = key
        self.isValid = isValid
        self.status = status
        self.expiresAt = expiresAt
        self.activationLimit = activationLimit
        self.activationUsage = activationUsage
        self.instanceId = instanceId
    }
}

/// Main license checking service — Polar.sh's customer-portal License Keys
/// API (`POST /v1/customer-portal/license-keys/validate`), same endpoint
/// shape MacGroom verified live: no `Authorization` header, a well-formed
/// request with a key that doesn't exist under `organizationId` returns
/// `404` (mapped to `.invalidLicenseKey`), not an auth error. Public and
/// client-safe by design — see
/// https://polar.apidocumentation.com/documentation/features/benefits/license-keys
public class LicenseChecker {
    private let urlSession: URLSession

    public init(urlSession: URLSession = URLSession.shared) {
        self.urlSession = urlSession
    }

    public func verify(
        licenseKey: String,
        useCache: Bool = true,
        cacheDuration: TimeInterval = 7 * 24 * 3600
    ) async throws -> License {
        guard PolarConfig.isConfigured else {
            throw LicenseCheckError.notConfigured
        }

        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespaces)

        return try await VerifyLock.shared.run(key: trimmedKey) { [self] in
            if useCache, let cached = self.getCachedLicense(trimmedKey) {
                if Date().timeIntervalSince(cached.0) < cacheDuration {
                    return cached.1
                } else {
                    self.clearCache(trimmedKey)
                }
            }

            let license = try await self.validateRemote(trimmedKey)
            self.setCachedLicense(trimmedKey, license)
            return license
        }
    }

    public func clearCache(_ licenseKey: String) {
        SecureLicenseCache.clearLicense(licenseKey)
    }

    public func clearAllCache() {
        SecureLicenseCache.clearAll()
    }

    // MARK: - Private Methods

    private func validateRemote(_ licenseKey: String) async throws -> License {
        var request = URLRequest(url: URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/validate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "key": licenseKey,
            "organization_id": PolarConfig.organizationId
        ])

        let (data, httpResponse) = try await send(request)

        guard httpResponse.statusCode == 200 else {
            throw mapErrorResponse(status: httpResponse.statusCode, data: data)
        }

        struct PolarLicenseKeyResponse: Decodable {
            let key: String
            let status: String
            let limitActivations: Int?
            let usage: Int?
            let expiresAt: String?

            enum CodingKeys: String, CodingKey {
                case key, status, usage
                case limitActivations = "limit_activations"
                case expiresAt = "expires_at"
            }
        }

        let response = try decode(PolarLicenseKeyResponse.self, from: data)

        return License(
            key: response.key,
            isValid: true,
            status: response.status,
            expiresAt: response.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            activationLimit: response.limitActivations,
            activationUsage: response.usage,
            instanceId: nil
        )
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LicenseCheckError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as URLError {
            throw LicenseCheckError.networkError(error)
        } catch let error as LicenseCheckError {
            throw error
        } catch {
            throw LicenseCheckError.codingError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LicenseCheckError.codingError(error)
        }
    }

    /// Polar's error responses come in two shapes: a `404` with
    /// `{"error": "ResourceNotFound", "detail": "Not found"}` for a key
    /// that doesn't exist under this organization, and a `422` with
    /// `{"detail": [{"msg": "...", "loc": [...]}]}` for a malformed
    /// request.
    private func mapErrorResponse(status: Int, data: Data) -> LicenseCheckError {
        let message = errorMessage(from: data)
        switch status {
        case 404:
            return .invalidLicenseKey
        case 403, 401:
            return .licenseDisabled
        default:
            if let message {
                let lower = message.lowercased()
                if lower.contains("expired") {
                    return .licenseExpired
                } else if lower.contains("disabled") || lower.contains("revoked") {
                    return .licenseDisabled
                } else if lower.contains("activation limit") || lower.contains("usage limit") {
                    return .activationLimitExceeded
                }
            }
            return .unknown(message ?? "License check failed (HTTP \(status)).")
        }
    }

    private func errorMessage(from data: Data) -> String? {
        struct FlatError: Decodable { let error: String?; let detail: String? }
        struct ValidationDetail: Decodable { let msg: String }
        struct ValidationError: Decodable { let detail: [ValidationDetail] }

        if let flat = try? JSONDecoder().decode(FlatError.self, from: data) {
            return flat.detail ?? flat.error
        }
        if let validation = try? JSONDecoder().decode(ValidationError.self, from: data) {
            return validation.detail.map(\.msg).joined(separator: "; ")
        }
        return String(data: data, encoding: .utf8)
    }

    private func getCachedLicense(_ licenseKey: String) -> (Date, License)? {
        SecureLicenseCache.readLicense(licenseKey)
    }

    private func setCachedLicense(_ licenseKey: String, _ license: License) {
        SecureLicenseCache.writeLicense(licenseKey, license)
    }
}

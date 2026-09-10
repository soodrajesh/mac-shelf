import Combine
import Foundation

/// Single source of truth for MacShelf Pro license status.
///
/// mac-tools has no `App`/`Scene` lifecycle (see `main.swift` — a plain
/// `NSApplicationDelegate` + `NSApplication.shared.run()`), so there's no
/// separate Settings `Scene` that would fail to inherit environment the way
/// mac-cleanup's does. Instead `AppDelegate` owns exactly one `LicenseState`
/// and hands the same instance to both the popover content and the
/// Settings window's `LicenseManagementView`, so a key entered in Settings
/// updates Pro gating in the popover immediately without a relaunch.
final class LicenseState: ObservableObject {
    static let licenseKeyDefaultsKey = "com.rajeshsood.macshelf.licenseKey"

    @Published private(set) var isProLicensed = false
    @Published private(set) var isVerifying = false
    @Published var verificationMessage = ""
    @Published var verificationError = false

    private let checker = LicenseChecker()

    var storedLicenseKey: String {
        get { UserDefaults.standard.string(forKey: Self.licenseKeyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.licenseKeyDefaultsKey) }
    }

    /// Called on launch and whenever the stored key changes (entered,
    /// updated, or cleared) — mirrors MacGroom's `.task(id: storedLicenseKey)`
    /// pattern but driven explicitly since this app has no SwiftUI `App`
    /// entry point to attach that modifier to.
    func refresh() async {
        let key = storedLicenseKey
        guard !key.isEmpty else {
            // Don't skip this — MacGroom shipped a bug once where clearing
            // the key left `isProLicensed` stuck at its prior value, so
            // removing a license didn't actually revoke Pro access until
            // relaunch. Always resolve explicitly, even for the empty case.
            isProLicensed = false
            return
        }

        isVerifying = true
        verificationMessage = ""
        defer { isVerifying = false }

        do {
            let license = try await checker.verify(licenseKey: key)
            isProLicensed = license.isValid
            verificationMessage = "License verified — MacShelf Pro unlocked."
            verificationError = false
        } catch {
            isProLicensed = false
            verificationMessage = (error as? LicenseCheckError)?.errorDescription ?? "License verification failed."
            verificationError = true
        }
    }

    func setLicenseKey(_ key: String) {
        storedLicenseKey = key
        Task { await refresh() }
    }

    func clear() {
        checker.clearCache(storedLicenseKey)
        storedLicenseKey = ""
        isProLicensed = false
        verificationMessage = "License key removed."
        verificationError = false
    }
}

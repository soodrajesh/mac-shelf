import SwiftUI

/// Same visual card pattern as mac-cleanup's `LicenseManagementView`: leading
/// icon (spinner while verifying, filled green check if active, hollow gray
/// circle if not) + two-line label ("MacTools Pro" headline / status caption)
/// inside a `Color(.controlBackgroundColor)` card, corner radius 8, plus a
/// green/red-tinted result banner below it.
struct LicenseManagementView: View {
    @ObservedObject var licenseState: LicenseState
    @State private var showLicenseEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if licenseState.isVerifying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: licenseState.isProLicensed ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(licenseState.isProLicensed ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("MacTools Pro")
                        .appFont(.headline)
                    Text(licenseState.isVerifying
                         ? "Verifying…"
                         : (licenseState.isProLicensed ? "License Active" : "Free Version"))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)

            if !licenseState.verificationMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: licenseState.verificationError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundColor(licenseState.verificationError ? .red : .green)
                    Text(licenseState.verificationMessage)
                        .appFont(.caption)
                }
                .padding(10)
                .background(licenseState.verificationError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .cornerRadius(6)
            }

            HStack(spacing: 8) {
                Button(action: { showLicenseEntry = true }) {
                    Text(licenseState.storedLicenseKey.isEmpty ? "Enter License Key" : "Update License")
                        .appFont(.body)
                }
                .buttonStyle(.bordered)

                if !licenseState.storedLicenseKey.isEmpty {
                    Button(action: licenseState.clear) {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("Remove stored license key")
                }

                Spacer()

                if let url = PolarConfig.checkoutURL {
                    Button("Buy MacTools Pro") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                    .appFont(.callout)
                }
            }
        }
        .sheet(isPresented: $showLicenseEntry) {
            LicenseEntrySheet(isPresented: $showLicenseEntry) { key in
                licenseState.setLicenseKey(key)
            }
        }
        .task { await licenseState.refresh() }
    }
}

struct LicenseEntrySheet: View {
    @Binding var isPresented: Bool
    var onLicenseEntered: (String) -> Void

    @State private var licenseKey = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Enter License Key")
                    .appFont(.title3)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Paste your license key from the email you received after purchase:")
                    .appFont(.body)
                    .foregroundStyle(.secondary)

                TextEditor(text: $licenseKey)
                    .appFont(.body, design: .monospaced)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
            }

            if !errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .appFont(.caption)
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save License") { saveLicense() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 450, height: 320)
    }

    private func saveLicense() {
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            errorMessage = "License key cannot be empty"
            return
        }
        let validCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard trimmedKey.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) else {
            errorMessage = "License key contains invalid characters"
            return
        }
        onLicenseEntered(trimmedKey)
        isPresented = false
    }
}

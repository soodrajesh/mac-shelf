import SwiftUI

/// System/Light/Dark, independent of the Mac's own appearance setting —
/// stored via `@AppStorage` and applied to the popover content's root view
/// via `.preferredColorScheme`. Ported from mac-cleanup's
/// `Views/SettingsView.swift` — see `DESIGN-SYSTEM.md`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Small/Medium/Large/Extra Large, backed by `@AppStorage` exactly like
/// `AppearanceMode`. Read via `Support.swift`'s `\.textScale` environment
/// key and applied by every view's `.appFont(_:weight:)` call.
enum TextSizeSetting: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:      return "Small"
        case .medium:      return "Medium"
        case .large:      return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .small:      return 0.9
        case .medium:      return 1.0
        case .large:      return 1.15
        case .extraLarge: return 1.3
        }
    }
}

import SwiftUI

/// The app's Text Size setting, in points-per-style plus a per-view
/// `.appFont(_:weight:)` modifier — deliberately *not* SwiftUI's
/// `.dynamicTypeSize`/`Font.TextStyle`, because Dynamic Type is an iOS/
/// iPadOS/tvOS/watchOS mechanism with no effect on macOS. This reimplements
/// the same idea with a real effect: a scale factor read from the
/// environment, applied to a fixed base point size per semantic role,
/// computed fresh at render time so Settings changes apply live.
///
/// Ported from mac-cleanup's `Support.swift` — see
/// `gogenops/apps/landing/mac-apps/DESIGN-SYSTEM.md`, which asks every app
/// in the line to carry its own copy of this small mechanism rather than
/// share a framework target.
private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// One semantic role → one base point size, matching macOS's own
/// approximate `NSFont.preferredFont(forTextStyle:)` values. The popover
/// content in this app is small and dense, so most call sites use
/// `.callout`/`.caption`/`.caption2` rather than the larger title styles.
enum AppFontStyle {
    case largeTitle, title, title2, title3
    case headline, body, callout, subheadline, footnote, caption, caption2

    var basePointSize: CGFloat {
        switch self {
        case .largeTitle:  return 26
        case .title:       return 22
        case .title2:      return 17
        case .title3:      return 15
        case .headline:    return 13
        case .body:        return 13
        case .callout:     return 12
        case .subheadline: return 11
        case .footnote:    return 10
        case .caption:     return 10
        case .caption2:    return 10
        }
    }

    /// SwiftUI's real `.headline` renders semibold, not regular — every
    /// other style here defaults to regular unless a caller overrides it.
    var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.textScale) private var scale
    let style: AppFontStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(.system(size: style.basePointSize * scale, weight: weight ?? style.defaultWeight))
    }
}

extension View {
    /// Replaces `.font(.caption)`, `.font(.headline)`, raw
    /// `.font(.system(size:))`, etc. throughout the app — every call site
    /// needs this instead for Settings' Text Size to have any real effect.
    /// `weight` is `nil` by default (not `.regular`) so styles with their
    /// own natural weight — just `.headline`, semibold — keep it unless a
    /// caller explicitly overrides.
    func appFont(_ style: AppFontStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFontModifier(style: style, weight: weight))
    }
}

import AppKit
import SwiftUI

/// Matches system menu-bar popovers (Weather, Control Center): popover material
/// with emphasized vibrancy from the first frame, not only after a control click.
struct PopoverVisualEffect: NSViewRepresentable {
    /// The Appearance setting's resolved `NSAppearance.Name`, or `nil` to
    /// follow the system — see `AppearanceMode.nsAppearanceName`. Without
    /// this the vibrancy material always follows the *system* appearance,
    /// so picking "Light" in Settings while macOS is in Dark Mode left this
    /// chrome dark (light-mode audit finding).
    var appearanceOverride: NSAppearance.Name?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.appearance = appearanceOverride.flatMap(NSAppearance.init(named:))
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.state = .active
        nsView.isEmphasized = true
        nsView.appearance = appearanceOverride.flatMap(NSAppearance.init(named:))
    }
}

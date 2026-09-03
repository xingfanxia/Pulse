import AppKit
import SwiftUI

/// The panel's surfaces as frosted dark glass: AppKit's HUD material blurred
/// from what is behind the window, darkened so type and rings stay legible
/// over anything, with the alert colour laid on as a translucent wash rather
/// than a solid block. Clipped to the shape the rail morphs through, so the
/// open/close animation still works.
struct ClauthFrostedSurface<S: Shape>: View {
    let shape: S
    var tint: Color?

    /// The berth folded to its sliver. A neutral sliver is a lighter frost
    /// with a bright edge so it can be found at the screen edge — no hue:
    /// a bare dark frost was too faint and an accent wash was worse than
    /// the black it replaced (AX 2026-09-03). The open rail stays plain
    /// dark frost; an alert keeps its colour.
    private var isSliver: Bool {
        (shape as? DockBerthShape).map { $0.openness < 0.5 } ?? false
    }

    var body: some View {
        ZStack {
            ClauthVisualEffect()
                .clipShape(shape)
            shape.fill(Color.black.opacity(isSliver ? 0.1 : 0.38))
            if let tint {
                shape.fill(tint.opacity(isSliver ? 0.7 : 0.55))
            } else if isSliver {
                shape.fill(Color.white.opacity(0.18))
            }
            shape.stroke(Color.white.opacity(isSliver ? 0.45 : 0.09), lineWidth: isSliver ? 1 : 0.5)
        }
    }
}

/// `NSVisualEffectView` in its dark HUD appearance, always active so it does
/// not fade when the window is not key — this panel never is.
struct ClauthVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

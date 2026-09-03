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

    var body: some View {
        ZStack {
            ClauthVisualEffect()
                .clipShape(shape)
            shape.fill(Color.black.opacity(0.38))
            if let tint {
                shape.fill(tint.opacity(0.55))
            }
            shape.stroke(Color.white.opacity(0.09), lineWidth: 0.5)
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

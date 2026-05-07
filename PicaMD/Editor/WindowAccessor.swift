import SwiftUI
import AppKit

/// Tiny `NSViewRepresentable` that hands the host SwiftUI view a
/// reference to its enclosing `NSWindow` once the view tree has been
/// added to a window. Used to apply window-level configuration
/// (tabbing mode, tabbing identifier, autosaveName, …) that SwiftUI
/// doesn't expose declaratively yet.
///
/// Place it in a `.background(WindowAccessor { window in … })` so it
/// stays out of the layout system. The closure runs once per window
/// — re-running it on every theme change would loop forever (we'd
/// re-set the same property and re-trigger the update).
struct WindowAccessor: NSViewRepresentable {
    final class Coordinator {
        var configured = false
    }

    let onWindow: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        // The view doesn't have a window at make-time. Defer until the
        // run-loop has placed it in the hierarchy.
        DispatchQueue.main.async { [weak v] in
            guard let v = v, let win = v.window else { return }
            if !context.coordinator.configured {
                context.coordinator.configured = true
                onWindow(win)
            }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // First-time path — `makeNSView` runs before the view enters
        // the hierarchy, so the deferred dispatch may have raced and
        // landed before `window` was set. Catch up here on the next
        // pass.
        guard !context.coordinator.configured else { return }
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView = nsView, let win = nsView.window else { return }
            if !context.coordinator.configured {
                context.coordinator.configured = true
                onWindow(win)
            }
        }
    }
}

import AppKit
import WebKit

// A call in a window of its own: the page out of its tab, wide, resizable,
// above everything and on whichever desktop you are looking at — Yab's call
// window for Zoom and Slack.
//
// Not Float's little window: that one is a video (one shape, black, its own
// controls, the page styled down to the video alone). A call site's page is
// the call, so it is lifted as it is, with nothing added over it and nothing
// taken away. The page never stops: it is the same page, in another window,
// which is also how it keeps sending to the other people on the call.
//
// Nothing here decides when to float. The tab says it is on a call (camera,
// microphone or screen in use — Stage.onCall), and the menu, or the setting
// that floats automatically, does the rest.

@MainActor
final class CallWindow {
    private var panel: NSPanel?
    private weak var web: NSView?
    private var closing = false

    /// Called when the window is closed by its own button, so the browser can
    /// put the page back and say it has.
    var onClose: (() -> Void)?
    var onReturn: (() -> Void)?

    var showing: Bool { panel != nil }
    var page: NSView? { web }

    /// Where its last window was, given back only while a screen still shows
    /// most of it.
    private static var remembered: NSRect? {
        get {
            guard let text = Store.settings.string(forKey: "call.frame") else { return nil }
            let frame = NSRectFromString(text)
            let shown = NSScreen.screens.contains {
                let seen = $0.visibleFrame.intersection(frame)
                return seen.width * seen.height > 0.5 * frame.width * frame.height
            }
            return frame.width > 200 && frame.height > 150 && shown ? frame : nil
        }
        set {
            if let newValue {
                Store.settings.set(NSStringFromRect(newValue), forKey: "call.frame")
            } else {
                Store.settings.removeObject(forKey: "call.frame")
            }
        }
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    func show(_ web: NSView, from parent: NSWindow?) {
        guard panel == nil else { return }
        self.web = web

        let room = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = CallWindow.remembered?.size ?? NSSize(width: min(1040, room.width - 80),
                                                         height: min(680, room.height - 80))
        var frame = CallWindow.remembered ?? NSRect(x: room.midX - size.width / 2,
                                                    y: room.midY - size.height / 2,
                                                    width: size.width, height: size.height)
        frame.size = size

        let panel = Panel(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                          backing: .buffered,
                          defer: false)
        panel.title = "Call"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 300)
        panel.delegate = Delegates.shared
        Delegates.shared.window = panel
        Delegates.shared.owner = self

        let ground = NSView(frame: NSRect(origin: .zero, size: frame.size))
        ground.wantsLayer = true
        ground.layer?.backgroundColor = NSColor.black.cgColor

        web.removeFromSuperview()
        web.frame = ground.bounds
        web.autoresizingMask = [.width, .height]
        ground.addSubview(web)

        panel.contentView = ground
        panel.orderFrontRegardless()
        self.panel = panel

        NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification,
                                               object: panel, queue: .main) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard let panel else { return }
                CallWindow.remembered = panel.frame
            }
        }
    }

    /// Back into its tab: the page leaves the window, the window goes, and the
    /// stage takes the page again on its next layout (the same self-healing
    /// the little window relies on).
    func hide() {
        guard let panel else { return }
        CallWindow.remembered = panel.frame
        closing = true
        if let web { web.removeFromSuperview() }
        panel.contentView = nil
        panel.close()
        self.panel = nil
        self.web = nil
        closing = false
    }

    fileprivate func closedByButton() {
        guard !closing else { return }
        onClose?()
    }

    /// The window's button brought it back: the tab it came from, in front.
    fileprivate func returned() {
        onReturn?()
    }

    private final class Delegates: NSObject, NSWindowDelegate {
        static let shared = Delegates()
        weak var window: NSWindow?
        weak var owner: CallWindow?

        func windowWillClose(_ notification: Notification) {
            owner?.closedByButton()
        }
    }
}

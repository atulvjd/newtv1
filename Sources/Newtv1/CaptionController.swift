import SwiftUI
import AppKit
import Combine

@MainActor
final class CaptionController {
    private var panel: NSPanel?
    private var subscription: AnyCancellable?
    init(speaker: AnswerSpeaker) {
        subscription = speaker.$caption.combineLatest(speaker.$speaking).receive(on: RunLoop.main).sink { [weak self] caption, speaking in
            guard let self else { return }
            guard speaking, !caption.isEmpty, UserDefaults.standard.object(forKey: "spokenCaptions") as? Bool ?? true else { self.panel?.orderOut(nil); return }
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
            guard let screen else { return }
            if self.panel == nil {
                let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.ignoresMouseEvents = true
                panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
                self.panel = panel
            }
            let width = min(760, screen.visibleFrame.width - 60)
            self.panel?.contentView = NSHostingView(rootView: Text(caption).font(.system(size: 20, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 24).padding(.vertical, 16).frame(width: width, height: 108).background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Newt spoken caption: " + caption))
            self.panel?.setFrame(CGRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 45, width: width, height: 108), display: true)
            self.panel?.orderFrontRegardless()
        }
    }
}

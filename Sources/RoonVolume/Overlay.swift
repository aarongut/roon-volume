import AppKit

final class Overlay {
  private let content = NSView()
  private let label = NSTextField(wrappingLabelWithString: "")
  private let icon = NSImageView()
  private var panel: NSPanel?
  private var hide: DispatchWorkItem?
  private var presentation = 0
  private var isPresenting = false

  func show(_ text: String, symbolName: String = "speaker.wave.2", restartTimer: Bool = true) {
    // Feedback can update a live presentation, but cannot bring an expired one back.
    guard restartTimer || isPresenting else { return }
    if restartTimer {
      hide?.cancel()
      presentation += 1
      isPresenting = true
    }
    if panel == nil { createPanel() }
    guard let panel else { return }

    label.stringValue = text
    icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    let maxWidth = min(600, (NSScreen.main?.visibleFrame.width ?? 640) - 40)
    let measured = label.sizeThatFits(
      NSSize(width: maxWidth - 52, height: .greatestFiniteMagnitude))
    let size = NSSize(width: ceil(measured.width) + 52, height: max(18, ceil(measured.height)) + 16)
    panel.setContentSize(size)
    content.frame = NSRect(origin: .zero, size: size)
    icon.frame = NSRect(x: 14, y: (size.height - 18) / 2, width: 18, height: 18)
    label.frame = NSRect(
      x: 40, y: (size.height - measured.height) / 2, width: size.width - 52,
      height: ceil(measured.height))
    if #available(macOS 26.0, *), let glass = panel.contentView as? NSGlassEffectView {
      glass.cornerRadius = min(size.height / 2, 24)
    } else {
      panel.contentView?.layer?.cornerRadius = min(size.height / 2, 24)
    }
    if let screen = NSScreen.main {
      panel.setFrameOrigin(
        NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 100))
    }
    if !panel.isVisible {
      panel.alphaValue = 0
      panel.orderFrontRegardless()
    }
    if restartTimer { setOpacity(1, duration: 0.12) }
    guard restartTimer else { return }

    let current = presentation
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.presentation == current else { return }
      self.isPresenting = false
      self.setOpacity(0, duration: 0.16) { [weak self] in
        guard let self, self.presentation == current else { return }
        self.panel?.orderOut(nil)
      }
    }
    hide = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
  }

  private func createPanel() {
    let panel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.ignoresMouseEvents = true

    label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
    label.textColor = .labelColor
    label.alignment = .center
    icon.contentTintColor = .labelColor
    icon.imageScaling = .scaleProportionallyDown
    content.autoresizingMask = [.width, .height]
    content.addSubview(icon)
    content.addSubview(label)

    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.style = .regular
      glass.contentView = content
      panel.contentView = glass
    } else {
      let effect = NSVisualEffectView()
      effect.material = .hudWindow
      effect.state = .active
      effect.blendingMode = .behindWindow
      effect.wantsLayer = true
      effect.layer?.masksToBounds = true
      effect.addSubview(content)
      panel.contentView = effect
    }
    self.panel = panel
  }

  private func setOpacity(
    _ opacity: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil
  ) {
    guard let panel else { return }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      panel.alphaValue = opacity
      completion?()
    } else {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        panel.animator().alphaValue = opacity
      } completionHandler: {
        completion?()
      }
    }
  }
}

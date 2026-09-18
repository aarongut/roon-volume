import AppKit

final class Overlay {
  private var panel: NSPanel?
  private var hide: DispatchWorkItem?
  func show(_ text: String, restartTimer: Bool = true) {
    if restartTimer { hide?.cancel() }
    if panel == nil {
      let p = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
        defer: false)
      p.level = .floating
      p.isOpaque = false
      p.backgroundColor = .clear
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      p.ignoresMouseEvents = true
      let effect = NSVisualEffectView(frame: p.contentView!.bounds)
      effect.material = .hudWindow
      effect.state = .active
      effect.wantsLayer = true
      effect.layer?.cornerRadius = 10
      effect.autoresizingMask = [.width, .height]
      p.contentView = effect
      panel = p
    }
    guard let panel else { return }
    for subview in panel.contentView?.subviews ?? [] {
      subview.removeFromSuperview()
    }
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 16, weight: .medium)
    label.alignment = .center
    let maxWidth = min(600, (NSScreen.main?.visibleFrame.width ?? 640) - 40)
    let measured = label.sizeThatFits(
      NSSize(width: maxWidth - 24, height: .greatestFiniteMagnitude))
    let size = NSSize(width: ceil(measured.width) + 24, height: ceil(measured.height) + 12)
    panel.setContentSize(size)
    label.frame = NSRect(x: 12, y: 6, width: size.width - 24, height: size.height - 12)
    panel.contentView?.addSubview(label)
    if let screen = NSScreen.main {
      panel.setFrameOrigin(
        NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 100))
    }
    panel.orderFrontRegardless()
    guard restartTimer else { return }
    let work = DispatchWorkItem { panel.orderOut(nil) }
    hide = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
  }
}

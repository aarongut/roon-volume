import AppKit
import VolumeCore

final class MediaKeys {
  // Return true to consume a complete media-key press, including key-up.
  var handler: ((VolumeAction, Bool, Bool) -> Bool)?
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  func start() -> Bool {
    stop()
    let mask = CGEventMask(1) << 14  // NX_SYSDEFINED, decoded through NSEvent.
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, type, event, context in
          guard let context else { return Unmanaged.passUnretained(event) }
          let owner = Unmanaged<MediaKeys>.fromOpaque(context).takeUnretainedValue()
          if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
          }
          guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined,
            ns.subtype.rawValue == 8
          else { return Unmanaged.passUnretained(event) }
          let code = (ns.data1 >> 16) & 0xffff
          let action: VolumeAction
          switch code {
          case 0: action = .up
          case 1: action = .down
          case 7: action = .mute
          default: return Unmanaged.passUnretained(event)
          }
          let flags = ns.data1 & 0xffff
          let down = ((flags >> 8) & 0xff) == 0x0a
          let repeating = (flags & 1) != 0
          return owner.handler?(action, down, repeating) == true
            ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    self.tap = tap
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }
  func stop() {
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
    }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil
    source = nil
  }
}

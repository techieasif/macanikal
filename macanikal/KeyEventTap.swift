import CoreGraphics
import Foundation
import IOKit.hid

/// Listens to global keyboard events via a listen-only CGEventTap running on a
/// dedicated high-priority thread, so keystrokes reach the sound engine with
/// minimal scheduling jitter. Requires the Input Monitoring permission.
final class KeyEventTap {
    /// (keyCode, isDown, isAutorepeat) — invoked on the tap thread.
    var handler: ((Int64, Bool, Bool) -> Void)?

    private var tapPort: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var pressedModifiers = Set<Int64>()

    static func hasPermission() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestPermission() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    var isRunning: Bool { tapPort != nil }

    @discardableResult
    func start() -> Bool {
        guard tapPort == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<KeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
            tap.process(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }

        tapPort = port
        let thread = Thread { [weak self] in
            guard let self, let port = self.tapPort else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "macanikal.eventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func stop() {
        if let port = tapPort {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let runLoop = tapRunLoop {
            CFRunLoopStop(runLoop)
        }
        tapPort = nil
        tapRunLoop = nil
        pressedModifiers.removeAll()
    }

    private func process(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port = tapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
        case .keyDown, .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            handler?(code, type == .keyDown, isRepeat)
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard let flag = Self.modifierFlags[code] else { return }
            let isDown = event.flags.contains(flag)
            // Caps lock reports the lock state, not the key state — treat every
            // press as a down so it still makes a sound.
            if code == 57 {
                handler?(code, true, false)
                return
            }
            if isDown {
                guard pressedModifiers.insert(code).inserted else { return }
            } else {
                guard pressedModifiers.remove(code) != nil else { return }
            }
            handler?(code, isDown, false)
        default:
            break
        }
    }

    private static let modifierFlags: [Int64: CGEventFlags] = [
        54: .maskCommand, 55: .maskCommand,
        56: .maskShift, 60: .maskShift,
        58: .maskAlternate, 61: .maskAlternate,
        59: .maskControl, 62: .maskControl,
        57: .maskAlphaShift,
        63: .maskSecondaryFn,
    ]
}

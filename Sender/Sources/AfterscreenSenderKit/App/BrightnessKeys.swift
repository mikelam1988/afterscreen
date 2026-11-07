import AppKit
import IOKit.hid

/// Handles brightness media keys and the F1/F2 events emitted by desktop keyboards.
/// The caller enables this only while streaming without a built-in brightness source.
/// A session event tap also receives them while another app has keyboard focus.
final class BrightnessKeys {
    struct Action: Equatable {
        let direction: Int
        let pressed: Bool
        let step: Double
    }
    // NX_SYSDEFINED / NX_SUBTYPE_AUX_CONTROL_BUTTONS, NX_KEYTYPE_BRIGHTNESS_*.
    static func action(subtype: Int16, data1: Int, flags: NSEvent.ModifierFlags) -> Action? {
        guard subtype == 8, flags.intersection([.command, .control]).isEmpty else { return nil }
        let key = (data1 >> 16) & 0xffff, state = (data1 >> 8) & 0xff
        guard key == 2 || key == 3, state == 0x0a || state == 0x0b else { return nil }
        return Action(direction: key == 2 ? 1 : -1, pressed: state == 0x0a,
                      step: flags.contains([.option, .shift]) ? 1.0 / 64 : 1.0 / 16)
    }
    static func functionAction(keyCode: Int64, pressed: Bool, flags: NSEvent.ModifierFlags) -> Action? {
        guard keyCode == 122 || keyCode == 120, flags.intersection([.command, .control]).isEmpty else { return nil }
        return Action(direction: keyCode == 120 ? 1 : -1, pressed: pressed,
                      step: flags.contains([.option, .shift]) ? 1.0 / 64 : 1.0 / 16)
    }
    static func adjusted(_ level: Double, action: Action) -> Double {
        min(1, max(0, level + Double(action.direction) * action.step))
    }

    var shouldHandle: () -> Bool = { false }
    var onPress: (Action) -> Void = { _ in }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var enabled = false
    private var hid: IOHIDManager?
    private var held = Set<Int>()
    private var repeatTimer: Timer?

    // Apple desktop keyboards report the physical sun keys as keyboard usages
    // F1/F2 even when macOS swallows them before creating a CGEvent.
    static func hidDirection(page: UInt32, usage: UInt32) -> Int? {
        switch (page, usage) {
        case (7, 58), (12, 0x70): return -1
        case (7, 59), (12, 0x6f): return 1
        default: return nil
        }
    }
    /// Several HID elements can report the same transition; do not double-step.
    static func transition(_ direction: Int, down: Bool, held: inout Set<Int>) -> Bool {
        if down { return held.insert(direction).inserted }
        held.remove(direction)
        return false
    }
    private func startHID() {
        guard hid == nil, IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6],
            [kIOHIDDeviceUsagePageKey: 12, kIOHIDDeviceUsageKey: 1]
        ] as CFArray)
        // Match exactly the two brightness controls; no text key input.
        IOHIDManagerSetInputValueMatchingMultiple(manager, [
            [kIOHIDElementUsagePageKey: 7, kIOHIDElementUsageKey: 58],
            [kIOHIDElementUsagePageKey: 7, kIOHIDElementUsageKey: 59],
            [kIOHIDElementUsagePageKey: 12, kIOHIDElementUsageKey: 0x6f],
            [kIOHIDElementUsagePageKey: 12, kIOHIDElementUsageKey: 0x70]
        ] as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context = context else { return }
            let owner = Unmanaged<BrightnessKeys>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            guard let direction = BrightnessKeys.hidDirection(page: IOHIDElementGetUsagePage(element), usage: IOHIDElementGetUsage(element)) else { return }
            owner.input(direction, down: IOHIDValueGetIntegerValue(value) != 0)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context = context else { return }
            Unmanaged<BrightnessKeys>.fromOpaque(context).takeUnretainedValue().clearHeld()
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess { hid = manager }
        else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
    }
    private func clearHeld() {
        held.removeAll(); repeatTimer?.invalidate(); repeatTimer = nil
    }
    private func input(_ direction: Int, down: Bool) {
        NSLog("[AfterscreenBrightness] HID direction=%d down=%d enabled=%d active=%d", direction, down ? 1 : 0, enabled ? 1 : 0, shouldHandle() ? 1 : 0)
        guard enabled, shouldHandle() else { return clearHeld() }
        let first = Self.transition(direction, down: down, held: &held)
        if held.isEmpty { repeatTimer?.invalidate(); repeatTimer = nil }
        guard first else { return }
        let flags = NSEvent.modifierFlags
        guard flags.intersection([.command, .control]).isEmpty else { return }
        let action = Action(direction: direction, pressed: true, step: flags.contains([.option, .shift]) ? 1.0 / 64 : 1.0 / 16)
        onPress(action)
        repeatTimer?.invalidate()
        let timer = Timer(fire: Date().addingTimeInterval(0.4), interval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.enabled, self.shouldHandle(), self.held.contains(direction), NSEvent.modifierFlags.intersection([.command, .control]).isEmpty else { return self.clearHeld() }
            self.onPress(action)
        }
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// No prompts here: permission is requested explicitly from the popover.
    @discardableResult func setEnabled(_ enabled: Bool) -> Bool {
        self.enabled = enabled
        if enabled { startHID() } else { clearHeld() }
        if enabled, tap == nil, AXIsProcessTrusted() {
            let mask = (CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue)
                | (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                   options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context = context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<BrightnessKeys>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            if let tap = tap {
                source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                if let source = source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
            }
        }
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: enabled) }
        return tap != nil && hid != nil && AXIsProcessTrusted()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if enabled, let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard enabled, shouldHandle() else { return Unmanaged.passUnretained(event) }
        let action: Action?
        if type.rawValue == NSEvent.EventType.systemDefined.rawValue, let key = NSEvent(cgEvent: event) {
            action = Self.action(subtype: key.subtype.rawValue, data1: key.data1, flags: key.modifierFlags)
        } else if type == .keyDown || type == .keyUp {
            // Read only the virtual key code, never typed text or Unicode strings.
            action = Self.functionAction(keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                                         pressed: type == .keyDown, flags: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
        } else {
            action = nil
        }
        guard let action = action else { return Unmanaged.passUnretained(event) }
        // HID owns the adjustment when available; the tap only suppresses the
        // duplicate system shortcut/HUD. Fall back for other media keyboards.
        if hid == nil, action.pressed { onPress(action) }
        // Consume key-up too, so macOS does not show an unrelated display HUD.
        return nil
    }
    deinit {
        repeatTimer?.invalidate()
        if let hid = hid {
            IOHIDManagerUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(hid, 0)
        }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = tap { CFMachPortInvalidate(tap) }
    }
}

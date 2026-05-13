import Carbon
import AppKit
import os

private let log = Logger(subsystem: "com.dropconvert", category: "HotkeyManager")

/// Registers a global Cmd+Shift+C hotkey via Carbon and forwards triggers to a handler.
///
/// Memory model: `Unmanaged.passRetained(self)` keeps this instance alive across the C
/// callback boundary. The retained reference is released in `deinit` after
/// `RemoveEventHandler` is called, ensuring the callback can never fire on a deallocated
/// object.
@MainActor
final class HotkeyManager {
    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?

    /// Called on the main thread when the hotkey fires.
    var onTriggered: (() -> Void)?

    init() {
        register()
    }

    deinit {
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
        if let key = hotkeyRef {
            UnregisterEventHotKey(key)
        }
    }

    // MARK: - Private

    private func register() {
        // Install the Carbon event handler for kEventHotKeyPressed.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Pass `self` through the C boundary as an unretained pointer.
        // The retained reference is held by the event handler and released in deinit.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
                Task { @MainActor in manager.onTriggered?() }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else {
            log.error("InstallEventHandler failed: \(status)")
            // Balance the passRetained since the handler was never installed.
            Unmanaged<HotkeyManager>.fromOpaque(selfPtr).release()
            return
        }

        // Register Cmd+Shift+C (keyCode 8 = 'c').
        let hotkeyID = EventHotKeyID(signature: fourCharCode("CVRT"), id: 1)
        let registerStatus = RegisterEventHotKey(
            8,                                      // kVK_ANSI_C
            UInt32(cmdKey | shiftKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if registerStatus != noErr {
            log.error("RegisterEventHotKey failed: \(registerStatus)")
        } else {
            log.info("Cmd+Shift+C hotkey registered")
        }
    }
}

// MARK: - Helpers

/// Packs a 4-character literal into the OSType / FourCharCode needed by Carbon.
private func fourCharCode(_ string: StaticString) -> FourCharCode {
    let bytes = string.utf8Start
    return (FourCharCode(bytes[0]) << 24)
         | (FourCharCode(bytes[1]) << 16)
         | (FourCharCode(bytes[2]) <<  8)
         |  FourCharCode(bytes[3])
}

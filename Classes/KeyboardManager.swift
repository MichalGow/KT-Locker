import Cocoa
import Carbon

class KeyboardManager {
    // Event taps
    private var keyboardEventTap: CFMachPort?
    private var systemEventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var systemRunLoopSource: CFRunLoopSource?
    private var localKeyboardMonitor: Any?
    private var systemKeyboardMonitor: Any?
    private var globalEventMonitor: Any?
    
    // Lock state
    var isKeyboardLocked = false
    var isSetup = false
    
    func setupEventMonitoring() {
        if isSetup {
            return
        }
        
        // Create event taps
        createKeyboardEventTap()
        createSystemEventTap()
        
        // Setup local monitor for Cmd+Q
        setupLocalKeyboardMonitor()
        
        // Setup NSEvent monitor for system keys (function keys)
        setupSystemKeyboardMonitor()
        
        // Add global monitor for system defined events
        setupGlobalEventMonitor()
        
        isSetup = true
    }
    
    func lockKeyboard(_ lock: Bool) {
        isKeyboardLocked = lock
        
        // Enable or disable keyboard event tap
        if let tap = keyboardEventTap {
            CGEvent.tapEnable(tap: tap, enable: lock)
        }
        
        // Enable or disable system event tap
        if let tap = systemEventTap {
            CGEvent.tapEnable(tap: tap, enable: lock)
        }
    }
    
    func cleanupEventTaps() {
        // Remove keyboard event tap
        if let tap = keyboardEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        
        // Remove system event tap
        if let tap = systemEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        
        // Remove run loop sources
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        if let source = systemRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        // Remove local monitors
        if let monitor = localKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        if let monitor = systemKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        isSetup = false
    }
    
    private func createKeyboardEventTap() {
        // Get a reference to self for the callback
        let mySelf = Unmanaged.passUnretained(self).toOpaque()
        
        // Define event mask for keyboard events
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)
        
        // Create HID level event tap (most comprehensive)
        keyboardEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let keyboardManager = Unmanaged<KeyboardManager>.fromOpaque(refcon!).takeUnretainedValue()
                
                if !keyboardManager.isKeyboardLocked {
                    return Unmanaged.passRetained(event)
                }
                
                // Always let Command+Q pass through to quit the app
                let flags = event.flags
                let isCommandPressed = flags.contains(.maskCommand)
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                
                if isCommandPressed && keyCode == 12 { // Command + Q (keycode 12 is 'q')
                    return Unmanaged.passRetained(event)
                }
                
                // Block all other keyboard events when locked
                return nil
            },
            userInfo: mySelf)
        
        if let tap = keyboardEventTap {
            // Create run loop source
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            
            // Add to run loop
            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: false)
            }
        }
    }
    
    private func createSystemEventTap() {
        // Get a reference to self for the callback
        let mySelf = Unmanaged.passUnretained(self).toOpaque()
        
        // Create system event tap for system defined events (includes media keys)
        systemEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << 14), // 14 is the raw value for systemDefined events
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let keyboardManager = Unmanaged<KeyboardManager>.fromOpaque(refcon!).takeUnretainedValue()
                
                if !keyboardManager.isKeyboardLocked {
                    return Unmanaged.passRetained(event)
                }
                
                // Block system events when locked
                return nil
            },
            userInfo: mySelf)
        
        if let tap = systemEventTap {
            // Create run loop source
            systemRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            
            // Add to run loop
            if let source = systemRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: false)
            }
        }
    }
    
    private func setupLocalKeyboardMonitor() {
        // Monitor for local keyboard events (backup for event tap)
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isKeyboardLocked else {
                return event
            }
            
            // Always let Command+Q pass through
            if event.modifierFlags.contains(.command) && event.keyCode == 12 {
                return event
            }
            
            // Block all other keyboard events
            return nil
        }
    }
    
    private func setupSystemKeyboardMonitor() {
        // Monitor for system keys (function keys, media keys)
        systemKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            guard let self = self, self.isKeyboardLocked else {
                return event
            }
            
            // Block system key events
            return nil
        }
    }
    
    private func setupGlobalEventMonitor() {
        // This is specifically for media keys (volume, brightness, etc.)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            guard let self = self, self.isKeyboardLocked else { return }
            
            // System defined events (volume, brightness, etc.)
            if event.type == .systemDefined {
                let data1 = event.data1
                
                // Extract key information
                let keyCode = (data1 & 0xFFFF0000) >> 16
                let keyFlags = data1 & 0x0000FFFF
                let keyIsDown = (keyFlags & 0xFF00) >> 8
                
                // Known system key codes:
                // 7 = brightness down
                // 8 = brightness up
                // 3 = volume mute
                // 2 = volume down
                // 1 = volume up
                // 0 = power key
                
                print("Detected system key: \(keyCode), flags: \(keyFlags), isDown: \(keyIsDown)")
                
                // We're just logging here - global monitors can't directly block events
                // But the system-level tap we set up earlier should do the blocking
            }
        }
    }
}

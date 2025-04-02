import Cocoa
import Carbon
import IOKit.hid
import ObjectiveC // Add this for objc_setAssociatedObject and objc_getAssociatedObject

class TouchpadManager {
    // Event tap for blocking touchpad events
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Lock state
    private(set) var isTouchpadLocked = false
    private(set) var isSetup = false

    // Gesture event monitors
    private var globalGestureMonitor: Any?
    private var localGestureMonitor: Any?
    private var trackpadEventMonitor: Any?
    private var lowLevelEventTap: CFMachPort?
    private var lowLevelRunLoopSource: CFRunLoopSource?

    // Position reset timer and state
    private var positionResetTimer: Timer?
    private var lastMousePosition: CGPoint = .zero
    private var isResettingPosition = false

    // Unlock handler
    var unlockHandler: (() -> Void)?

    // Notification observer
    private var escKeyObserver: NSObjectProtocol?

    // Scroll wheel monitor and tap
    private var scrollWheelMonitor: Any?
    private var scrollWheelTap: CFMachPort?
    private var scrollWheelRunLoopSource: CFRunLoopSource?

    // HID Manager for direct touchpad blocking
    private var hidManager: IOHIDManager?

    init() {
        // Initialize mouse position
        lastMousePosition = NSEvent.mouseLocation

        // Set up notification observer for ESC key
        escKeyObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ESCKeyPressed"),
            object: nil,
            queue: .main) { [weak self] _ in
                guard let self = self, self.isTouchpadLocked else { return }

                // Call unlock handler
                self.unlockHandler?()
            }
    }

    deinit {
        // Remove notification observer
        if let observer = escKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setupEventMonitoring() {
        if isSetup {
            return
        }

        // Create event tap
        createTouchpadEventTap()

        isSetup = true
    }

    func cleanupEventTaps() {
        // Remove event tap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        // Remove run loop source
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        // Remove notification observer
        if let observer = escKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            escKeyObserver = nil
        }

        // Stop position reset timer
        stopPositionResetTimer()

        // Remove gesture monitors
        removeGestureEventMonitoring()

        eventTap = nil
        runLoopSource = nil
        isSetup = false
    }

    func lockTouchpad(_ lock: Bool, window: NSWindow?, button: NSButton?) {
        isTouchpadLocked = lock
        
        if lock {
            // Setup comprehensive monitoring first (to catch ALL events)
            setupComprehensiveEventMonitoring()
            
            // Setup gesture monitoring first
            setupGestureEventMonitoring()
            
            // Setup keyboard monitoring (now handled at application level)
            setupKeyboardEventMonitoring()
            
            // Setup HID-level touchpad blocking (most comprehensive approach)
            setupHIDTouchpadBlocking()
            
            // Create and enable the touchpad event tap as fallback
            createTouchpadEventTap()
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            
            // Setup timer to force mouse position
            setupPositionResetTimer(window: window, button: button)
            
            // Force position immediately
            forceMousePosition(window: window, button: button)
        } else {
            // Clean up keyboard monitors
            cleanupKeyboardMonitors()
            
            // Clean up HID touchpad blocking
            cleanupHIDTouchpadBlocking()
            
            // Clean up all event tap resources
            removeEventTapResources()
            
            // Clean up timer
            positionResetTimer?.invalidate()
            positionResetTimer = nil
        }
    }

    // MARK: - Position Reset Timer

    private func setupPositionResetTimer(window: NSWindow?, button: NSButton?) {
        // Stop any existing timer
        stopPositionResetTimer()

        guard let window = window, let button = button else { return }

        // Create a timer that runs every 5ms to reset mouse position
        positionResetTimer = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { [weak self] _ in
            guard let self = self,
                  self.isTouchpadLocked,
                  !self.isResettingPosition else { return }

            self.isResettingPosition = true

            // Force the window to be the key window and focused
            if !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }

            // Force the mouse position to be centered over the button
            self.forceMousePosition(window: window, button: button)

            self.isResettingPosition = false
        }

        // Ensure the timer is added to the common run loop modes
        RunLoop.current.add(positionResetTimer!, forMode: .common)
    }

    private func stopPositionResetTimer() {
        positionResetTimer?.invalidate()
        positionResetTimer = nil
    }

    private func forceMousePosition(window: NSWindow?, button: NSButton?) {
        guard let window = window, let button = button else { return }

        // Calculate the target position - center of the button in screen coordinates
        let buttonFrame = button.convert(button.bounds, to: nil)
        let windowFrame = window.frame
        let buttonCenterX = windowFrame.origin.x + buttonFrame.midX
        let buttonCenterY = NSScreen.main!.frame.height - (windowFrame.origin.y + buttonFrame.midY)
        let targetPoint = CGPoint(x: buttonCenterX, y: buttonCenterY)

        // Force the mouse position to be centered over the button
        let currentPos = NSEvent.mouseLocation
        if currentPos.x != targetPoint.x || currentPos.y != targetPoint.y {
            CGWarpMouseCursorPosition(targetPoint)
            self.lastMousePosition = targetPoint
        }
    }

    // MARK: - Keyboard Event Monitoring

    func setupKeyboardEventMonitoring() {
        // Note: Keyboard monitoring is now handled in AppDelegate
        // This method is kept for backward compatibility
    }

    func cleanupKeyboardMonitors() {
        // Note: Keyboard monitoring is now handled in AppDelegate
        // This method is kept for backward compatibility
    }

    // MARK: - Gesture Event Monitoring

    private func setupGestureEventMonitoring() {
        // Remove any existing monitors
        removeGestureEventMonitoring()

        // Create a mask for ALL possible gesture event types
        let allGestureTypesMask: NSEvent.EventTypeMask = [
            .gesture,
            .magnify,
            .swipe,
            .rotate,
            .beginGesture,
            .endGesture,
            .smartMagnify,
            .pressure,
            .directTouch,   // Direct touch events (Force Touch)
            .tabletPoint,   // Tablet events
            .tabletProximity
        ]

        // 1. Add a global monitor for ALL possible gesture events
        globalGestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: allGestureTypesMask) { _ in
            // Just block the events, no logging needed
        }

        // 2. Add a local monitor for ALL possible gesture events in the current app
        localGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: allGestureTypesMask) { event in
            // Return the event unchanged - we're blocking at lower levels
            return event
        }
        
        // 3. Special specific handling for scroll wheel events which may bypass other blockers
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { _ in
            // Just block the events, no logging needed
            return nil
        }
    }
    
    private func setupScrollWheelBlockingTap() {
        // Get a reference to self for the callback
        let mySelf = Unmanaged.passUnretained(self).toOpaque()
        
        // Create a dedicated tap just for scroll wheel events
        let scrollMask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue)
        
        scrollWheelTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: scrollMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                // Get a reference to self from the userInfo
                guard let userInfo = userInfo else {
                    return Unmanaged.passRetained(event)
                }
                
                let mySelf = Unmanaged<TouchpadManager>.fromOpaque(userInfo).takeUnretainedValue()
                
                // Only block events if the touchpad is locked
                guard mySelf.isTouchpadLocked else {
                    return Unmanaged.passRetained(event)
                }
                
                // Block scroll wheel events when touchpad is locked
                return nil
            },
            userInfo: mySelf)
        
        // If tap creation failed, log error and return
        guard let tap = scrollWheelTap else {
            return
        }
        
        // Create a run loop source from the tap
        scrollWheelRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        // Add the run loop source to the current run loop
        if let runLoopSource = scrollWheelRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeGestureEventMonitoring() {
        // Remove global gesture monitor
        if let monitor = globalGestureMonitor {
            NSEvent.removeMonitor(monitor)
            globalGestureMonitor = nil
        }

        // Remove local gesture monitor
        if let monitor = localGestureMonitor {
            NSEvent.removeMonitor(monitor)
            localGestureMonitor = nil
        }

        // Remove trackpad event monitor
        if let monitor = trackpadEventMonitor {
            NSEvent.removeMonitor(monitor)
            trackpadEventMonitor = nil
        }

        // Clean up the low-level event tap
        if let tap = lowLevelEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            lowLevelEventTap = nil
        }

        // Clean up the run loop source
        if let source = lowLevelRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            lowLevelRunLoopSource = nil
        }
        
        // Clean up scroll wheel monitor
        if let monitor = scrollWheelMonitor {
            NSEvent.removeMonitor(monitor)
            scrollWheelMonitor = nil
        }
    }

    // MARK: - Comprehensive Event Monitoring

    private func setupComprehensiveEventMonitoring() {
        // Create a monitor for essential event types
        let essentialEventsMask: NSEvent.EventTypeMask = [
            .scrollWheel, .swipe, .gesture, .magnify, .rotate, .beginGesture, .endGesture
        ]
        
        // Global monitor for essential events
        NSEvent.addGlobalMonitorForEvents(matching: essentialEventsMask) { _ in
            // Just block the events, no logging needed
        }
        
        // Local monitor for essential events
        NSEvent.addLocalMonitorForEvents(matching: essentialEventsMask) { event in
            // Return the event unchanged - we're blocking at lower levels
            return event
        }
    }

    // MARK: - HID Manager Setup for Direct Touchpad Blocking

    private func setupHIDTouchpadBlocking() {
        // Create IOHIDManager to match Multitouch devices
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            return
        }
        
        // Match all multitouch devices (like internal trackpads)
        let matchingDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_Digitizer,
            kIOHIDDeviceUsageKey as String: kHIDUsage_Dig_TouchPad
        ]
        
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        
        // Register input callback to block all events
        IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, _ in
            // Block ALL multitouch events by simply ignoring them
            // No logging needed in production
        }, nil)
        
        // Schedule on runloop and open IOHIDManager with device seizure
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        
        // Open with seize device option to take complete control
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    }
    
    private func cleanupHIDTouchpadBlocking() {
        guard let manager = hidManager else { return }
        
        // Unregister callback
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        
        // Close manager and release device
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        // Unschedule from runloop
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        
        hidManager = nil
    }

    // MARK: - Event Tap Creation

    private func createTouchpadEventTap() {
        // Get a reference to self for the callback
        let mySelf = Unmanaged.passUnretained(self).toOpaque()

        // Define comprehensive event masks for touchpad/mouse events including gestures
        // Movement events
        let movementMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue) |
                           (1 << CGEventType.leftMouseDragged.rawValue) |
                           (1 << CGEventType.rightMouseDragged.rawValue) |
                           (1 << CGEventType.otherMouseDragged.rawValue)

        // Click events
        let clickMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.leftMouseUp.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseUp.rawValue) |
                        (1 << CGEventType.otherMouseDown.rawValue) |
                        (1 << CGEventType.otherMouseUp.rawValue)

        // Scroll and tablet events - critical for gestures
        let scrollAndGestureMask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue) |
                                  (1 << CGEventType.tabletPointer.rawValue) |
                                  (1 << CGEventType.tabletProximity.rawValue)

        // IMPORTANT: No longer include keyboard events in the tap - we need ESC to work!
        // Only block touchpad related events
                                  
        // Combine all masks to capture all possible touchpad/mouse/gesture events
        let eventMask: CGEventMask = movementMask | clickMask | scrollAndGestureMask

        // Try HID-level tap first - this is more comprehensive for hardware events
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // Critical: Using defaultTap to actually block events, not just listen
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let touchpadManager = Unmanaged<TouchpadManager>.fromOpaque(refcon!).takeUnretainedValue()

                if !touchpadManager.isTouchpadLocked {
                    return Unmanaged.passRetained(event)
                }

                // Block all events when touchpad is locked
                // No logging needed in production
                
                // Forcing mouse position for visual feedback
                if let window = NSApplication.shared.mainWindow,
                   let viewController = window.contentViewController as? MainViewController,
                   let button = viewController.touchpadLockButton {
                     touchpadManager.forceMousePosition(window: window, button: button)
                }
                
                return nil  // This is what actually blocks the event
            },
            userInfo: mySelf)

        if let tap = eventTap {
            // Create run loop source
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

            // Add to run loop
            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)  // CRITICAL: Enable the tap!
            }
        } else {
            // Try session-level tap as fallback
            eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,  // Critical: Using defaultTap to actually block events
                eventsOfInterest: eventMask,
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    let touchpadManager = Unmanaged<TouchpadManager>.fromOpaque(refcon!).takeUnretainedValue()

                    if !touchpadManager.isTouchpadLocked {
                        return Unmanaged.passRetained(event)
                    }

                    // Block all touchpad/mouse events when locked
                    // No logging needed in production
                    
                    // Forcing mouse position for visual feedback
                    if let window = NSApplication.shared.mainWindow,
                       let viewController = window.contentViewController as? MainViewController,
                       let button = viewController.touchpadLockButton {
                         touchpadManager.forceMousePosition(window: window, button: button)
                    }
                    
                    return nil  // This is what actually blocks the event
                },
                userInfo: mySelf)

            if let tap = eventTap {
                // Create run loop source
                runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

                // Add to run loop
                if let source = runLoopSource {
                    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                    CGEvent.tapEnable(tap: tap, enable: true)  // CRITICAL: Enable the tap!
                }
            } else {
                // Failed to create any event tap! Touchpad locking will be limited.
            }
        }
    }

    // MARK: - Low-level event tap callback
    
    private static func lowLevelTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
        // Get a reference to self from the refcon
        guard let refcon = refcon else {
            return Unmanaged.passRetained(event)
        }
        
        let mySelf = Unmanaged<TouchpadManager>.fromOpaque(refcon).takeUnretainedValue()
        
        // Only block events if the touchpad is locked
        guard mySelf.isTouchpadLocked else {
            return Unmanaged.passRetained(event)
        }
        
        // Block all mouse/touchpad events - no detailed logging needed in production
        return nil
    }

    // MARK: - Cleanup Methods
    
    private func removeEventTapResources() {
        // Disable the main event tap if it exists
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        
        // Clean up the run loop source
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        
        // Clean up low-level event tap resources
        if let tap = lowLevelEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            lowLevelEventTap = nil
        }
        
        // Clean up the low-level run loop source
        if let source = lowLevelRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            lowLevelRunLoopSource = nil
        }
        
        // Clean up scroll wheel specific resources
        if let tap = scrollWheelTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            scrollWheelTap = nil
        }
        
        if let source = scrollWheelRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            scrollWheelRunLoopSource = nil
        }
        
        if let monitor = scrollWheelMonitor {
            NSEvent.removeMonitor(monitor)
            scrollWheelMonitor = nil
        }
    }
}

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    internal var mainController: MainViewController!
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create window
        createWindow()

        // Create main controller
        mainController = MainViewController()

        // Set window's content view to the main controller's view
        window.contentView = mainController.view

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Setup keyboard monitor for ESC and ENTER keys
        setupKeyboardMonitor()

        // Set window delegate to handle window close events
        window.delegate = self
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Remove keyboard monitor
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Clean up resources
        mainController.cleanupResources()
    }

    private func setupKeyboardMonitor() {
        // Monitor keyboard events for ESC key (53) and ENTER key (36)
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for ESC key (53) or ENTER key (36)
            if (event.keyCode == 53 || event.keyCode == 36) &&
               self?.mainController.touchpadManager.isTouchpadLocked == true {
                print("Key pressed (\(event.keyCode)), unlocking touchpad")
                self?.mainController.unlockTouchpadOnly()
                return nil // Consume the event to prevent window closure
            }
            return event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if mainController.touchpadManager.isTouchpadLocked {
            print("AppDelegate: Preventing window close while touchpad locked")
            return false
        }
        return true
    }

    private func createWindow() {
        // Create window with specific style mask
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        // Configure window appearance
        window.center()
        window.title = "KT Locker v1.0"
        window.isReleasedWhenClosed = false
    }

    // Update close button state based on touchpad lock state
    func updateCloseButtonState(locked: Bool) {
        window.standardWindowButton(.closeButton)?.isEnabled = !locked
    }
}

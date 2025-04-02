import Cocoa

// Custom NSApplication subclass to handle ESC and ENTER keys when touchpad is locked
class KTLockerApplication: NSApplication {
    // Override sendEvent to intercept ESC and ENTER keys
    override func sendEvent(_ event: NSEvent) {
        // Only intercept keyboard events
        if event.type == .keyDown && (event.keyCode == 53 || event.keyCode == 36) {
            // Get the main controller from the app delegate
            if let appDelegate = delegate as? AppDelegate,
               let mainController = appDelegate.mainController,
               mainController.touchpadManager.isTouchpadLocked {
                
                print("KTLockerApplication: Intercepting key \(event.keyCode) in sendEvent")
                
                // Unlock the touchpad without closing the window
                mainController.unlockTouchpadOnly()
                
                // Don't pass the event to the system
                return
            }
        }
        
        // For all other events, use default behavior
        super.sendEvent(event)
    }
}

// Initialize our custom application
let app = KTLockerApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

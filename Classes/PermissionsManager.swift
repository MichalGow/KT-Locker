import Cocoa
import ApplicationServices

class PermissionsManager {
    private let permissionCheckedKey = "lastPermissionCheck"
    
    // Check if app has accessibility permissions
    func checkAccessibilityPermissions() -> Bool {
        // Dictionary with options to check
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        
        // Check if process is trusted for accessibility
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        return accessibilityEnabled
    }
    
    // Request accessibility permissions by opening System Preferences
    func requestAccessibilityPermissions() {
        // Create URL to open Security & Privacy preferences directly to Accessibility
        let prefPaneUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        
        // Open the URL
        NSWorkspace.shared.open(prefPaneUrl)
        
        // Set timestamp for last check
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: permissionCheckedKey)
    }
}

import Cocoa

class MainViewController: NSViewController {

    // UI elements
    private var statusView: NSView!
    private var instructionsLabel: NSTextField!
    private var keyboardLockButton: NSButton!
    internal var touchpadLockButton: NSButton! // Changed to internal for access from TouchpadManager
    private var quitButton: NSButton!

    // Managers
    private var keyboardManager: KeyboardManager!
    internal var touchpadManager: TouchpadManager!
    private var permissionsManager: PermissionsManager!

    // Window management
    private var windowFocusTimer: Timer?
    private var windowObserver: NSObjectProtocol?
    private var permissionCheckTimer: Timer?

    // UI state
    private var permissionContainerView: NSView?
    private var overlayWindow: NSWindow?
    private var overlayClickMonitor: Any?
    private var shouldCloseAfterUnlock = true

    override func loadView() {
        // Create view
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Create managers
        keyboardManager = KeyboardManager()
        touchpadManager = TouchpadManager()
        permissionsManager = PermissionsManager()

        // Setup UI
        setupUI()

        // Check permissions
        checkPermissionsAndUpdateUI()

        // Start permission check timer
        startPermissionCheckTimer()

        // Setup window observer
        setupWindowObserver()
    }

    // Clean up resources
    func cleanupResources() {
        // Clean up managers
        keyboardManager.cleanupEventTaps()
        touchpadManager.cleanupEventTaps()

        // Clean up timers
        stopWindowFocusTimer()
        permissionCheckTimer?.invalidate()

        // Clean up observers
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Clean up overlay
        removeOverlayWindow()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Setup container with modern design
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        containerView.layer?.cornerRadius = 12

        // Title removed as it's redundant with window title bar

        // Add status view with modern design
        statusView = NSView(frame: NSRect.zero)
        statusView.wantsLayer = true
        statusView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        statusView.layer?.cornerRadius = 8
        statusView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusView)

        // Add instructions label with modern font
        instructionsLabel = NSTextField(labelWithString: "Select which input device to lock.")
        instructionsLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        instructionsLabel.textColor = NSColor.secondaryLabelColor
        instructionsLabel.alignment = .center
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        statusView.addSubview(instructionsLabel)

        // Create button container for better layout
        let buttonContainer = NSView(frame: NSRect.zero)
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        statusView.addSubview(buttonContainer)

        // Add keyboard lock button with icon
        keyboardLockButton = createIconButton(iconName: "keyboard", title: "Lock Keyboard", action: #selector(toggleKeyboardLock))
        buttonContainer.addSubview(keyboardLockButton)

        // Add touchpad lock button with icon
        touchpadLockButton = createIconButton(iconName: "hand.tap.fill", title: "Lock Touchpad", action: #selector(toggleTouchpadLock))
        buttonContainer.addSubview(touchpadLockButton)

        // Add quit button with modern styling
        quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        quitButton.bezelStyle = .rounded
        quitButton.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(quitButton)

        // Setup constraints for modern layout
        NSLayoutConstraint.activate([
            // Status view constraints - now constrained to top of container since title is removed
            statusView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            statusView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            statusView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            // Instructions label constraints
            instructionsLabel.topAnchor.constraint(equalTo: statusView.topAnchor, constant: 20),
            instructionsLabel.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 20),
            instructionsLabel.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -20),

            // Button container constraints
            buttonContainer.topAnchor.constraint(equalTo: instructionsLabel.bottomAnchor, constant: 20),
            buttonContainer.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 20),
            buttonContainer.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -20),
            buttonContainer.bottomAnchor.constraint(equalTo: statusView.bottomAnchor, constant: -20),

            // Keyboard button constraints
            keyboardLockButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            keyboardLockButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            keyboardLockButton.widthAnchor.constraint(equalToConstant: 180),
            keyboardLockButton.heightAnchor.constraint(equalToConstant: 100),

            // Touchpad button constraints
            touchpadLockButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
            touchpadLockButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            touchpadLockButton.widthAnchor.constraint(equalToConstant: 180),
            touchpadLockButton.heightAnchor.constraint(equalToConstant: 100),

            // Quit button constraints
            quitButton.topAnchor.constraint(equalTo: statusView.bottomAnchor, constant: 20),
            quitButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            quitButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
            quitButton.widthAnchor.constraint(equalToConstant: 100)
        ])

        // Set initial button states
        updateKeyboardButtonUI(isLocked: false)
        updateTouchpadButtonUI(isLocked: false)

        // Add container to view
        containerView.frame = view.bounds
        containerView.autoresizingMask = [.width, .height]
        view.addSubview(containerView)
    }

    private func createIconButton(iconName: String, title: String, action: Selector) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 180, height: 100))
        button.title = ""
        button.bezelStyle = .regularSquare
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.separatorColor.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = action

        // Create vertical stack for icon and label
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Create icon image view
        let iconImageView = NSImageView()
        iconImageView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: title)
        iconImageView.image?.size = NSSize(width: 48, height: 48)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        // Create label
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        // Add to stack
        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(label)

        // Add stack to button
        button.addSubview(stackView)

        // Center stack in button
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48)
        ])

        // Store the label as an associated object for later access
        objc_setAssociatedObject(button, AssociatedKeys.buttonLabel, label, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Store the icon as an associated object for later access
        objc_setAssociatedObject(button, AssociatedKeys.buttonIcon, iconImageView, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return button
    }

    // MARK: - UI Updates

    private func updateTouchpadButtonUI(isLocked: Bool) {
        // Get the label and icon from associated objects
        if let label = objc_getAssociatedObject(touchpadLockButton!, AssociatedKeys.buttonLabel) as? NSTextField,
           let iconView = objc_getAssociatedObject(touchpadLockButton!, AssociatedKeys.buttonIcon) as? NSImageView {

            if isLocked {
                label.stringValue = "Unlock Touchpad"
                label.textColor = NSColor.systemRed
                iconView.contentTintColor = NSColor.systemRed
                touchpadLockButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.1).cgColor
            } else {
                label.stringValue = "Lock Touchpad"
                label.textColor = NSColor.systemGreen
                iconView.contentTintColor = NSColor.systemGreen
                touchpadLockButton.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.1).cgColor
            }
        }

        // Update instructions based on lock state
        if isLocked {
            instructionsLabel.stringValue = "Press ESC or Enter to unlock touchpad."
            instructionsLabel.textColor = NSColor.systemRed
        } else if !keyboardManager.isKeyboardLocked {
            instructionsLabel.stringValue = "Select which input device to lock."
            instructionsLabel.textColor = NSColor.secondaryLabelColor
        }
    }

    private func updateKeyboardButtonUI(isLocked: Bool) {
        // Get the label and icon from associated objects
        if let label = objc_getAssociatedObject(keyboardLockButton!, AssociatedKeys.buttonLabel) as? NSTextField,
           let iconView = objc_getAssociatedObject(keyboardLockButton!, AssociatedKeys.buttonIcon) as? NSImageView {

            if isLocked {
                label.stringValue = "Unlock Keyboard"
                label.textColor = NSColor.systemRed
                iconView.contentTintColor = NSColor.systemRed
                keyboardLockButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.1).cgColor
            } else {
                label.stringValue = "Lock Keyboard"
                label.textColor = NSColor.systemGreen
                iconView.contentTintColor = NSColor.systemGreen
                keyboardLockButton.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.1).cgColor
            }
        }

        // Update instructions based on lock state
        if isLocked {
            instructionsLabel.stringValue = "Click keyboard icon again to unlock it."
            instructionsLabel.textColor = NSColor.systemRed
        } else if !touchpadManager.isTouchpadLocked {
            instructionsLabel.stringValue = "Select which input device to lock."
            instructionsLabel.textColor = NSColor.secondaryLabelColor
        }
    }

    // MARK: - Actions

    @objc private func toggleKeyboardLock() {
        // Can't lock keyboard if touchpad is locked
        if touchpadManager.isTouchpadLocked {
            return
        }

        let newLockState = !keyboardManager.isKeyboardLocked

        if newLockState {
            // Bring window to front before locking
            view.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Set window level to floating when locked
            view.window?.level = .floating

            // Start the window focus timer
            startWindowFocusTimer()

            // Update instructions
            instructionsLabel.stringValue = "Click the keyboard button to unlock it"
            instructionsLabel.textColor = NSColor.systemRed

            // Disable touchpad lock button
            touchpadLockButton.isEnabled = false
            touchpadLockButton.alphaValue = 0.5
        } else {
            // Reset window level when unlocked
            view.window?.level = .normal

            // Stop the window focus timer
            stopWindowFocusTimer()

            // Update instructions
            instructionsLabel.stringValue = "Select which input device to lock"
            instructionsLabel.textColor = NSColor.secondaryLabelColor

            // Enable touchpad lock button
            touchpadLockButton.isEnabled = true
            touchpadLockButton.alphaValue = 1.0
        }

        // Lock/unlock keyboard
        keyboardManager.lockKeyboard(newLockState)

        // Update UI
        updateKeyboardButtonUI(isLocked: newLockState)
    }

    @objc private func toggleTouchpadLock(_ sender: NSButton) {
        // Toggle touchpad lock state
        if touchpadManager.isTouchpadLocked {
            unlockTouchpad()
        } else {
            lockTouchpad()
        }
    }

    func lockTouchpad() {
        // Lock touchpad
        touchpadManager.lockTouchpad(true, window: view.window, button: touchpadLockButton)

        // Update UI
        updateTouchpadButtonUI(isLocked: true)

        // Update close button state
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateCloseButtonState(locked: true)
        }
    }

    func unlockTouchpad() {
        // Unlock touchpad
        touchpadManager.lockTouchpad(false, window: nil, button: nil)

        // Update UI
        updateTouchpadButtonUI(isLocked: false)

        // Update close button state
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateCloseButtonState(locked: false)
        }

        // Close window if needed
        if shouldCloseAfterUnlock {
            DispatchQueue.main.async { [weak self] in
                self?.view.window?.close()
            }
        }
    }

    // MARK: - Permissions Management

    private func startPermissionCheckTimer() {
        // Check permissions every 2 seconds
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermissionsAndUpdateUI()
        }
    }

    private func checkPermissionsAndUpdateUI() {
        let hasPermissions = permissionsManager.checkAccessibilityPermissions()

        // Setup managers if permissions granted
        if hasPermissions {
            if !keyboardManager.isSetup {
                keyboardManager.setupEventMonitoring()
                updateKeyboardButtonUI(isLocked: keyboardManager.isKeyboardLocked)
            }

            if !touchpadManager.isSetup {
                touchpadManager.setupEventMonitoring()
                updateTouchpadButtonUI(isLocked: touchpadManager.isTouchpadLocked)
            }
        }

        // Update permission message
        updatePermissionMessage(hasPermissions)

        // Enable or disable lock buttons based on permissions
        keyboardLockButton.isEnabled = hasPermissions && !touchpadManager.isTouchpadLocked
        touchpadLockButton.isEnabled = hasPermissions && !keyboardManager.isKeyboardLocked

        // Update alpha for visual feedback
        if !hasPermissions {
            keyboardLockButton.alphaValue = 0.5
            touchpadLockButton.alphaValue = 0.5
        } else {
            keyboardLockButton.alphaValue = touchpadManager.isTouchpadLocked ? 0.5 : 1.0
            touchpadLockButton.alphaValue = keyboardManager.isKeyboardLocked ? 0.5 : 1.0
        }
    }

    private func updatePermissionMessage(_ hasPermissions: Bool) {
        // Remove existing permission message
        permissionContainerView?.removeFromSuperview()
        permissionContainerView = nil

        // Show permission message if needed
        if !hasPermissions {
            // Create container view
            permissionContainerView = NSView(frame: NSRect(x: 60, y: 80, width: view.frame.width - 120, height: 120))
            guard let containerView = permissionContainerView else { return }

            // Style container
            containerView.wantsLayer = true
            containerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
            containerView.layer?.cornerRadius = 10
            containerView.layer?.borderWidth = 1
            containerView.layer?.borderColor = NSColor(calibratedWhite: 0.9, alpha: 1.0).cgColor
            containerView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.1).cgColor
            containerView.layer?.shadowOffset = NSSize(width: 0, height: 2)
            containerView.layer?.shadowRadius = 4
            containerView.layer?.shadowOpacity = 1.0

            // Add icon
            let iconView = NSImageView(frame: NSRect(x: (containerView.frame.width - 32) / 2, y: 75, width: 32, height: 32))
            if let lockImage = NSImage(named: NSImage.cautionName) {
                iconView.image = lockImage
            }
            containerView.addSubview(iconView)

            // Add title
            let titleLabel = NSTextField(frame: NSRect(x: 15, y: 50, width: containerView.frame.width - 30, height: 20))
            titleLabel.stringValue = "Accessibility Permission Required"
            titleLabel.isEditable = false
            titleLabel.isBordered = false
            titleLabel.drawsBackground = false
            titleLabel.alignment = .center
            titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
            titleLabel.textColor = NSColor.controlTextColor
            containerView.addSubview(titleLabel)

            // Add description
            let descLabel = NSTextField(frame: NSRect(x: 15, y: 30, width: containerView.frame.width - 30, height: 20))
            descLabel.stringValue = "This app needs accessibility access to control input devices"
            descLabel.isEditable = false
            descLabel.isBordered = false
            descLabel.drawsBackground = false
            descLabel.alignment = .center
            descLabel.font = NSFont.systemFont(ofSize: 12)
            descLabel.textColor = NSColor.secondaryLabelColor
            containerView.addSubview(descLabel)

            // Add button to request permissions
            let permissionButton = NSButton(frame: NSRect(x: (containerView.frame.width - 200) / 2, y: 10, width: 200, height: 30))
            permissionButton.title = "Open Accessibility Settings"
            permissionButton.bezelStyle = .rounded
            permissionButton.target = self
            permissionButton.action = #selector(requestPermissions)
            permissionButton.wantsLayer = true
            permissionButton.layer?.cornerRadius = 5
            containerView.addSubview(permissionButton)

            view.addSubview(containerView)
        }
    }

    // MARK: - Window Focus Management

    private func setupWindowObserver() {
        // Observe when window becomes non-key (loses focus)
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: view.window,
            queue: .main) { [weak self] _ in
                guard let self = self else { return }
                let isLocked = self.keyboardManager.isKeyboardLocked || self.touchpadManager.isTouchpadLocked

                if isLocked {
                    // If we're locked and window loses focus, bring it back immediately
                    print("Window lost focus while locked, bringing it back")
                    self.view.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }

    private func startWindowFocusTimer() {
        // Stop any existing timer
        stopWindowFocusTimer()

        // Create a timer that checks every 0.5 seconds if the window is active
        windowFocusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let isLocked = self.keyboardManager.isKeyboardLocked || self.touchpadManager.isTouchpadLocked

            if isLocked && !(self.view.window?.isKeyWindow ?? false) {
                print("Window not key window while locked, bringing it to front")
                self.view.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func stopWindowFocusTimer() {
        windowFocusTimer?.invalidate()
        windowFocusTimer = nil
    }

    // MARK: - Overlay Window Management

    private func createOverlayWindow() {
        // Remove any existing overlay
        removeOverlayWindow()

        guard let mainScreen = NSScreen.main, let mainWindow = view.window else { return }

        // Create a borderless window covering the entire screen
        overlayWindow = NSWindow(
            contentRect: mainScreen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: mainScreen
        )

        guard let overlayWindow = overlayWindow else { return }

        // Make it transparent and floating above everything except our main window
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.level = .modalPanel
        overlayWindow.ignoresMouseEvents = false

        // Create transparent content view
        let overlayView = NSView(frame: mainScreen.frame)
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor

        // Add the button area to allow clicks
        if let button = touchpadLockButton {
            // Get button frame in screen coordinates
            let buttonFrame = button.convert(button.bounds, to: nil)
            let windowFrame = mainWindow.frame
            let buttonScreenFrame = NSRect(
                x: windowFrame.origin.x + buttonFrame.origin.x,
                y: windowFrame.origin.y + buttonFrame.origin.y,
                width: buttonFrame.width,
                height: buttonFrame.height
            )

            // Create a tracking area
            let trackingArea = NSTrackingArea(
                rect: buttonScreenFrame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            overlayView.addTrackingArea(trackingArea)
        }

        overlayWindow.contentView = overlayView

        // Add local event monitor to handle clicks
        overlayClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]) { [weak self] event in
            guard let self = self,
                  self.touchpadManager.isTouchpadLocked,
                  let button = self.touchpadLockButton,
                  let mainWindow = self.view.window else {
                return event
            }

            // Convert button frame to screen coordinates
            let buttonFrame = button.convert(button.bounds, to: nil)
            let windowFrame = mainWindow.frame
            let buttonScreenFrame = NSRect(
                x: windowFrame.origin.x + buttonFrame.origin.x,
                y: windowFrame.origin.y + buttonFrame.origin.y,
                width: buttonFrame.width,
                height: buttonFrame.height
            )

            // Check if click is in the button
            let locationInScreen = NSEvent.mouseLocation
            if NSPointInRect(locationInScreen, buttonScreenFrame) {
                // Allow click to pass through to the button
                print("Allowing click on touchpad button from overlay")

                // Force main window to front
                self.view.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)

                // Return the event to allow it to be processed
                return event
            }

            // Block all other clicks
            print("Blocking click via overlay: \(event.type.rawValue)")
            return nil
        }

        // Show the overlay
        overlayWindow.orderFront(nil)
    }

    private func removeOverlayWindow() {
        // Remove existing overlay window
        overlayWindow?.close()
        overlayWindow = nil

        // Remove overlay monitor
        if let monitor = overlayClickMonitor {
            NSEvent.removeMonitor(monitor)
            overlayClickMonitor = nil
        }
    }

    // MARK: - ESC Key Handling - COMPLETE OVERRIDE

    // Override keyDown to handle ESC key (keyCode 53) for unlocking
    override func keyDown(with event: NSEvent) {
        // Check for ESC key (keyCode 53)
        if event.keyCode == 53 {
            print("MainViewController: BLOCKING ESC key in keyDown")

            if touchpadManager.isTouchpadLocked {
                print("MainViewController: Touchpad is locked, unlocking...")

                // Directly unlock the touchpad without calling toggleTouchpadLock
                unlockTouchpad()
            }

            // ALWAYS consume ESC key events to prevent app closure
            // Don't pass the event to super to prevent it from closing the app
            return
        } else {
            super.keyDown(with: event)
        }
    }

    // Override cancelOperation to prevent ESC from closing the window
    override func cancelOperation(_ sender: Any?) {
        print("MainViewController: Intercepting cancelOperation")

        if touchpadManager.isTouchpadLocked {
            print("MainViewController: Touchpad is locked, unlocking...")

            // Directly unlock the touchpad without calling toggleTouchpadLock
            unlockTouchpad()
        }

        // NEVER call super to prevent default ESC behavior
        // This is critical - we never want ESC to close the window
    }

    // Override performKeyEquivalent to catch ESC key
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Check for ESC key (keyCode 53)
        if event.keyCode == 53 {
            print("MainViewController: Intercepting ESC key in performKeyEquivalent")

            if touchpadManager.isTouchpadLocked {
                // Directly unlock the touchpad without calling toggleTouchpadLock
                unlockTouchpad()
            }

            return true // ALWAYS indicate that we handled the key
        }
        return super.performKeyEquivalent(with: event)
    }

    // Override doCommand to catch ESC key
    override func doCommand(by selector: Selector) {
        print("MainViewController: doCommand called with selector: \(selector)")

        // Check if this is the cancel selector (ESC key)
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            print("MainViewController: Intercepting cancel selector in doCommand")

            if touchpadManager.isTouchpadLocked {
                // Directly unlock the touchpad without calling toggleTouchpadLock
                unlockTouchpad()
            }

            return // NEVER call super for cancel operations
        }

        super.doCommand(by: selector)
    }

    // Override interpretKeyEvents to catch ESC key
    override func interpretKeyEvents(_ eventArray: [NSEvent]) {
        var shouldCallSuper = true

        for event in eventArray {
            if event.keyCode == 53 {
                print("MainViewController: Intercepting ESC key in interpretKeyEvents")

                if touchpadManager.isTouchpadLocked {
                    // Directly unlock the touchpad without calling toggleTouchpadLock
                    unlockTouchpad()
                }

                shouldCallSuper = false
                break
            }
        }

        if shouldCallSuper {
            super.interpretKeyEvents(eventArray)
        }
    }

    // Override resignFirstResponder to prevent window from closing
    override func resignFirstResponder() -> Bool {
        if touchpadManager.isTouchpadLocked {
            print("MainViewController: Preventing resignFirstResponder while touchpad locked")
            return false
        }
        return super.resignFirstResponder()
    }

    // MARK: - Unlock Methods

    /// Unlocks the touchpad only without toggling the window state
    func unlockTouchpadOnly() {
        // Unlock touchpad
        touchpadManager.lockTouchpad(false, window: nil, button: nil)

        // Update UI
        updateTouchpadButtonUI(isLocked: false)

        // Update close button state
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateCloseButtonState(locked: false)
        }

        // Don't close the window - this is the key difference from unlockTouchpad()
    }

    // MARK: - Associated Keys

    private struct AssociatedKeys {
        static let buttonLabel: UnsafeRawPointer = UnsafeRawPointer(bitPattern: "buttonLabel".hashValue)!
        static let buttonIcon: UnsafeRawPointer = UnsafeRawPointer(bitPattern: "buttonIcon".hashValue)!
    }

    // MARK: - View Lifecycle

    @objc private func quitApp() {
        // Ensure devices are unlocked
        if keyboardManager.isKeyboardLocked {
            keyboardManager.lockKeyboard(false)
        }

        if touchpadManager.isTouchpadLocked {
            touchpadManager.lockTouchpad(false, window: view.window, button: touchpadLockButton)
        }

        // Cleanup resources
        cleanupResources()

        // Quit app
        NSApp.terminate(nil)
    }

    @objc private func requestPermissions() {
        permissionsManager.requestAccessibilityPermissions()
    }
}

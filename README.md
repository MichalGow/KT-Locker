# KT Locker

A modern macOS utility for locking your keyboard and touchpad while cleaning them. This application was completely created by AI.

## Features

- Lock your keyboard with a single click
- Lock your touchpad with a single click using multi-layered blocking technology:
  - HID-level blocking for comprehensive touchpad event prevention
  - Event tap system for additional protection
  - Multi-finger gesture and swipe blocking
  - Mouse position locking to prevent cursor movement
- Modern UI with visual indicators showing lock status
- Automatic permission handling with clear guidance
- Prevents locking both devices simultaneously
- Conditional window focus (stays on top only when locked)
- Easily unlock with ESC key (touchpad) or clicking the button (keyboard)

## Technical Implementation

KT Locker uses several advanced macOS technologies to provide comprehensive input blocking:

- **IOHIDManager**: Direct hardware-level blocking of touchpad events
- **CGEventTap**: System-level event interception for both keyboard and touchpad
- **NSEvent Monitoring**: Application-level event monitoring for gestures and special events
- **Position Reset Timer**: Continuous cursor position enforcement

## Requirements (run)

- macOS 10.14 or later

## (Optional) requiremens (build)

- Xcode 12.0 or later

## Building the Application

1. Open Terminal and navigate to the project directory:
   ```
   cd /path/to/KTLockerApp
   ```

2. Run the build script:
   ```
   ./build.sh
   ```

3. Open the app:
   ```
   open "KT Locker.app"
   ```

## Usage

1. Launch the application
2. Grant accessibility permissions when prompted (required to control keyboard and touchpad input)

3. To lock your keyboard:
   - Click the "Lock Keyboard" button
   - The button will turn red and the window will stay on top
   - Click the "Unlock Keyboard" button to unlock it

4. To lock your touchpad:
   - Click the "Lock Touchpad" button
   - The button will turn red and the window will stay on top
   - Press the ESC or Enter key to unlock the touchpad

5. To exit the application:
   - Click the "Quit" button

## Permissions

This application requires Accessibility permissions to function properly. A clear guidance will be displayed if permissions are not granted, with a direct button to open the relevant System Settings page.

## AI-Powered Development

This application was entirely developed by AI. The development process included:

- Designing the architecture and UI
- Implementing complex event handling systems
- Creating multi-layered input blocking mechanisms
- Optimizing for production use with minimal resource usage
- Debugging and refining the codebase

The used AI tools were:

- Most of the grunt: **Windsurf** by [Codeium](https://codeium.com/)
- Debugging: [**Roo-Code**](https://github.com/RooVetGit/Roo-Code) powered by [Requesty](https://www.requesty.ai/)
- Consultation in times of need: **ChatGPT-4.5** by [OpenAI](https://openai.com/)

## License

This project is open source and available under the MIT License.

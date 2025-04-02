import Cocoa
import AppKit

// This script follows Apple's exact specifications for macOS app icons:
// - 1024x1024 pixel canvas
// - Artwork within 824x824 pixel area
// - Corner radius of 185.4 pixels

// Load the source icon
guard let sourceIcon = NSImage(contentsOfFile: "manual_icons/icon.png") else {
    print("Error: Could not load manual_icons/icon.png")
    exit(1)
}

// Create a 1024x1024 canvas
let canvasSize: CGFloat = 1024
let artworkSize: CGFloat = 824
let cornerRadius: CGFloat = 185.4

let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))

image.lockFocus()

// Fill with transparent background
NSColor.clear.set()
NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

// Calculate positioning to center the artwork
let padding = (canvasSize - artworkSize) / 2
let artworkRect = NSRect(x: padding, y: padding, width: artworkSize, height: artworkSize)

// Create the rounded rect path with Apple's specified corner radius
let path = NSBezierPath(roundedRect: artworkRect, xRadius: cornerRadius, yRadius: cornerRadius)

// Clip to the rounded rectangle
path.addClip()

// Draw the source icon within the artwork area
sourceIcon.draw(in: artworkRect, 
               from: NSRect(origin: .zero, size: sourceIcon.size),
               operation: .copy, 
               fraction: 1.0)

image.unlockFocus()

// Create iconset directory
let fileManager = FileManager.default
let iconsetDir = "AppleIcon.iconset"
try? fileManager.removeItem(atPath: iconsetDir)
try? fileManager.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true, attributes: nil)

// Save the master icon
if let tiffData = image.tiffRepresentation,
   let bitmapImage = NSBitmapImageRep(data: tiffData),
   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
    try! pngData.write(to: URL(fileURLWithPath: "\(iconsetDir)/icon_512x512@2x.png"))
    print("Created master icon (1024x1024)")
}

// Create all required sizes
let sizes = [16, 32, 128, 256, 512]

for size in sizes {
    let scaledImage = NSImage(size: NSSize(width: size, height: size))
    
    scaledImage.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
              from: NSRect(origin: .zero, size: image.size),
              operation: .copy,
              fraction: 1.0)
    scaledImage.unlockFocus()
    
    if let tiffData = scaledImage.tiffRepresentation,
       let bitmapImage = NSBitmapImageRep(data: tiffData),
       let pngData = bitmapImage.representation(using: .png, properties: [:]) {
        
        // Save standard size
        let filename = "\(iconsetDir)/icon_\(size)x\(size).png"
        try! pngData.write(to: URL(fileURLWithPath: filename))
        print("Created \(filename)")
        
        // Save retina size if not the largest
        if size < 512 {
            let retinaSize = size * 2
            let retinaImage = NSImage(size: NSSize(width: retinaSize, height: retinaSize))
            
            retinaImage.lockFocus()
            image.draw(in: NSRect(x: 0, y: 0, width: retinaSize, height: retinaSize),
                      from: NSRect(origin: .zero, size: image.size),
                      operation: .copy,
                      fraction: 1.0)
            retinaImage.unlockFocus()
            
            if let retinaTiffData = retinaImage.tiffRepresentation,
               let retinaBitmapImage = NSBitmapImageRep(data: retinaTiffData),
               let retinaPngData = retinaBitmapImage.representation(using: .png, properties: [:]) {
                let retinaFilename = "\(iconsetDir)/icon_\(size)x\(size)@2x.png"
                try! retinaPngData.write(to: URL(fileURLWithPath: retinaFilename))
                print("Created \(retinaFilename)")
            }
        }
    }
}

// Convert to ICNS
print("Converting to ICNS format...")
let process = Process()
process.launchPath = "/usr/bin/iconutil"
process.arguments = ["-c", "icns", iconsetDir]
process.launch()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Successfully created AppleIcon.icns")
    print("To use this icon, update build.sh to copy AppleIcon.icns instead of AppIcon.icns")
} else {
    print("Error creating ICNS file")
}

import AVFoundation
import AppKit
import Combine
import Darwin
import Foundation
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
    static let contextualProcessing = Self("contextualProcessing")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let audioRecorder = AudioRecorder.shared
    var popover: NSPopover?
    var toastWindow: ToastWindow?
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        print("🐛 [MAIN] COMPILED IN DEBUG MODE!")
        #else
        print("🚀 [MAIN] COMPILED IN RELEASE MODE!")
        #endif
        
        // Initialize debug manager first
        _ = DebugManager.shared
        
        // TEST APP CATEGORY
        logInfo(.app, "🔄 TEST APP CATEGORY - checking if APP logs work")
        print("🎯 [MAIN] Testing APP category logging...")
        
        // Log startup information using new debug system
        logInfo(.system, "=====================================================")
        logInfo(.system, "WhisperRecorder starting")
        logInfo(.system, "Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        logInfo(.system, "Resource path: \(Bundle.main.resourcePath ?? "unknown")")
        logInfo(.system, "Frameworks path: \(Bundle.main.privateFrameworksPath ?? "unknown")")
        logInfo(.system, "Running as app bundle: \(ProcessInfo.processInfo.environment["WHISPER_APP_BUNDLE"] != nil)")

        if let resourcesPath = ProcessInfo.processInfo.environment["WHISPER_RESOURCES_PATH"] {
            logInfo(.system, "Custom resources path: \(resourcesPath)")
        }

        if let libraryPath = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"] {
            logDebug(.system, "DYLD_LIBRARY_PATH: \(libraryPath)")
        }

        if let insertLibraries = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] {
            logDebug(.system, "DYLD_INSERT_LIBRARIES: \(insertLibraries)")
        }

        logInfo(.system, "Application did finish launching")

        // Check for updates
        logInfo(.system, "Checking for updates")
        AutoUpdater.shared.onUpdateStatusChanged = {
            DispatchQueue.main.async {
                if let popover = self.popover, popover.isShown {
                    popover.contentViewController = NSHostingController(
                        rootView: PopoverView(audioRecorder: self.audioRecorder))
                }
            }
        }
        AutoUpdater.shared.checkForUpdates()

        // Check bundle resources
        if let bundlePath = Bundle.main.resourcePath {
            logDebug(.system, "Bundle resource path: \(bundlePath)")
            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
                logDebug(.system, "Bundle resources: \(contents.joined(separator: ", "))")
            } else {
                logWarning(.system, "Failed to list bundle resources")
            }
        }

        // Check frameworks directory
        if let bundlePath = Bundle.main.privateFrameworksPath {
            logDebug(.system, "Bundle frameworks path: \(bundlePath)")
            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
                logDebug(.system, "Bundle frameworks: \(contents.joined(separator: ", "))")
            } else {
                logWarning(.system, "Failed to list bundle frameworks")
            }
        }

        // Set up default keyboard shortcut
        logInfo(.system, "Setting up keyboard shortcut")
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [self] in
            logDebug(.ui, "Keyboard shortcut triggered")
            audioRecorder.toggleRecording()
        }
        
        // Set up contextual processing shortcut
        KeyboardShortcuts.onKeyDown(for: .contextualProcessing) { [self] in
            logDebug(.ui, "Contextual processing shortcut triggered")
            audioRecorder.processWithClipboardContext()
        }

        if KeyboardShortcuts.getShortcut(for: .toggleRecording) == nil {
            logInfo(.system, "Setting default keyboard shortcut")
            KeyboardShortcuts.setShortcut(
                .init(.e, modifiers: [.command, .shift]), for: .toggleRecording)
        }
        
        if KeyboardShortcuts.getShortcut(for: .contextualProcessing) == nil {
            logInfo(.system, "Setting default contextual processing shortcut")
            KeyboardShortcuts.setShortcut(
                .init(.w, modifiers: [.command, .shift]), for: .contextualProcessing)
        }

        // Handle status updates
        logInfo(.ui, "Setting up status update handler")
        audioRecorder.onStatusUpdate = {
            self.updateMenuBar()
        }

        // Make app visible in dock for easier debugging
        logInfo(.system, "Setting activation policy to regular (visible in dock)")
        NSApp.setActivationPolicy(.regular)

        // Set up status item in the menu bar
        logInfo(.ui, "Setting up menu bar")
        setupMenuBar()
        
        // Initialize toast window
        logInfo(.ui, "Setting up toast window")
        setupToastWindow()
        
        logInfo(.system, "Application startup complete")

        let mainMenu = NSMenu()

        // Edit menu (for Paste)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(
            withTitle: "Paste", action: #selector(AppDelegate.paste(_:)), keyEquivalent: "v")

        // Set as app main menu
        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        logWarning(.system, "Application will terminate - performing emergency audio restore")
        SystemAudioManager.shared.emergencyRestore()
        
        // Clean up event monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func setupMenuBar() {
        logDebug(.ui, "Creating status item")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            logDebug(.ui, "Configuring status item button")
            button.image = createCompatibleImage(
                systemSymbol: "waveform.circle",
                accessibilityDescription: "WhisperRecorder")
            button.action = #selector(togglePopover(_:))
            button.target = self
        } else {
            logWarning(.ui, "Failed to get status item button")
        }

        // Create popover
        logDebug(.ui, "Creating popover")
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 340, height: 400)  // Updated size for card design
        popover?.behavior = .applicationDefined  // Application controls when popover closes
        popover?.contentViewController = NSHostingController(
            rootView: PopoverView(audioRecorder: audioRecorder))  // Use new card-based view
    }

    private func setupToastWindow() {
        toastWindow = ToastWindow()
        print("🎯 [MAIN] ToastWindow created: \(toastWindow != nil)")
        print("🎯 [MAIN] ToastWindow address: \(Unmanaged.passUnretained(toastWindow!).toOpaque())")
        
        // Observe ToastManager state changes
        let cancellable = ToastManager.shared.$isShowing
            .sink { [weak self] isShowing in
                print("🎯 [MAIN] === TOAST OBSERVER TRIGGERED ===")
                print("🎯 [MAIN] Toast isShowing changed to: \(isShowing)")
                print("🎯 [MAIN] ToastManager message: '\(ToastManager.shared.message)'")
                print("🎯 [MAIN] ToastManager position: \(ToastManager.shared.position)")
                print("🎯 [MAIN] ToastWindow exists: \(self?.toastWindow != nil)")
                print("🎯 [MAIN] Thread: \(Thread.isMainThread ? "Main" : "Background")")
                
                DispatchQueue.main.async {
                    print("🎯 [MAIN] In main queue - updating toast content")
                    self?.toastWindow?.updateToastContent()
                    
                    if isShowing {
                        print("🎯 [MAIN] About to show toast at position: \(ToastManager.shared.position)")
                        self?.toastWindow?.showToastAtPosition(ToastManager.shared.position)
                        print("🎯 [MAIN] showToastAtPosition called")
                    } else {
                        print("🎯 [MAIN] About to hide toast")
                        self?.toastWindow?.orderOut(nil)
                        print("🎯 [MAIN] orderOut called")
                    }
                    print("🎯 [MAIN] === OBSERVER COMPLETE ===")
                }
            }
        
        // Keep the cancellable (in a real app, you'd store this)
        objc_setAssociatedObject(self, "toastCancellable", cancellable, .OBJC_ASSOCIATION_RETAIN)
        print("🎯 [MAIN] Toast observer setup complete")
    }

    @objc func togglePopover(_ sender: AnyObject) {
        if statusItem?.button != nil {
            if popover?.isShown == true {
                closePopover()
            } else {
                showPopover()
            }
        }
    }
    
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover?.contentViewController?.view.window?.makeKey()
        
        // Start monitoring for clicks outside the popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }
    
    private func closePopover() {
        popover?.performClose(nil)
        
        // Stop monitoring for clicks
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func updateMenuBar() {
        logDebug(.ui, "Updating menu bar")
        DispatchQueue.main.async {
            if let button = self.statusItem?.button {
                switch self.audioRecorder.statusDescription {
                case "Recording...":
                    button.image = createCompatibleImage(
                        systemSymbol: "waveform.circle.fill",
                        accessibilityDescription: "Recording")
                    if let image = button.image {
                        button.image?.isTemplate = false
                        button.image = image.tinted(with: .systemRed)
                    }
                case "Transcribing...":
                    button.image = createCompatibleImage(
                        systemSymbol: "waveform.circle.fill",
                        accessibilityDescription: "Transcribing")
                    if let image = button.image {
                        button.image?.isTemplate = false
                        button.image = image.tinted(with: .systemBlue)
                    }
                case "Reformatting...":
                    button.image = createCompatibleImage(
                        systemSymbol: "text.bubble.fill",
                        accessibilityDescription: "Reformatting")
                    if let image = button.image {
                        button.image?.isTemplate = false
                        button.image = image.tinted(with: .systemPurple)
                    }
                default:
                    button.image = createCompatibleImage(
                        systemSymbol: "waveform.circle",
                        accessibilityDescription: "WhisperRecorder")
                    button.image?.isTemplate = true
                }
            }

            // If popover is open, update it
            if let popover = self.popover, popover.isShown {
                popover.contentViewController = NSHostingController(
                    rootView: PopoverView(audioRecorder: self.audioRecorder))  // Use new card-based view
            }
        }
    }
}

// Helper view for SF Symbols compatibility
struct CompatibleSystemImage: View {
    let systemName: String
    let color: Color?

    init(_ systemName: String, color: Color? = nil) {
        self.systemName = systemName
        self.color = color
    }

    var body: some View {
        if #available(macOS 11.0, *) {  // Changed from 13.0 to 11.0 for broader compatibility
            Image(systemName: systemName)
                .foregroundColor(color)
        } else {
            // Use a simple circle as fallback for older macOS versions
            Circle()
                .foregroundColor(color)
                .frame(width: 16, height: 16)
        }
    }
}

// Helper extension to tint NSImage
extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()

        color.set()

        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)

        image.unlockFocus()
        return image
    }
}

// Helper function to create compatible NSImage
func createCompatibleImage(systemSymbol: String, accessibilityDescription: String?) -> NSImage? {
    if #available(macOS 11.0, *) {  // Changed from 13.0 to 11.0
        return NSImage(
            systemSymbolName: systemSymbol, accessibilityDescription: accessibilityDescription)
    } else {
        // Fallback for older macOS versions - use template images
        let imageName: String
        switch systemSymbol {
        case "waveform.circle":
            imageName = "NSStatusAvailable"
        case "waveform.circle.fill":
            imageName = "NSStatusAvailable"
        case "text.bubble.fill":
            imageName = "NSStatusAvailable"
        default:
            imageName = "NSStatusAvailable"
        }
        let image = NSImage(named: imageName)
        image?.isTemplate = true
        image?.accessibilityDescription = accessibilityDescription
        return image
    }
}

extension AppDelegate {
    @objc func paste(_ sender: Any?) {
        if let window = NSApp.keyWindow,
            let responder = window.firstResponder as? NSText
        {
            responder.paste(sender)
        } else {
            // Removed NSSound.beep() - causes double sound during auto-paste
            // NSSound.beep()  // Optional: play a beep if no responder
        }
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

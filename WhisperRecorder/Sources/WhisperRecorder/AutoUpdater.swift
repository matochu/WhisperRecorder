import Foundation
import SwiftUI

private struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let preRelease: String?

    init?(versionString: String) {
        // Parse version string like "1.2.3" or "1.2.3-beta1"
        let components = versionString.split(separator: "-", maxSplits: 1)
        let numbers = components[0].split(separator: ".")

        guard numbers.count == 3,
            let major = Int(numbers[0]),
            let minor = Int(numbers[1]),
            let patch = Int(numbers[2])
        else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.preRelease = components.count > 1 ? String(components[1]) : nil
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Pre-release versions are considered less than the regular version
        switch (lhs.preRelease, rhs.preRelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case (let l?, let r?): return l < r
        }
    }
}

class AutoUpdater: NSObject {
    static let shared = AutoUpdater()

    private let updateInfoURL =
        "https://drive.google.com/uc?export=download&id=1LzvpJiZY9Wy373204WyGaQGwH8ipJbxF"
    private let userDefaultsLastCheckKey = "LastUpdateCheckDate"
    private let userDefaultsCurrentVersionKey = "CurrentAppVersion"

    private(set) var isCheckingForUpdates = false
    private(set) var isDownloadingUpdate = false
    private(set) var downloadProgress: Double = 0.0
    private(set) var updateAvailable = false
    private(set) var latestVersion: String = ""
    private(set) var updateURL: String = ""
    private(set) var updateFileName: String = ""

    var onUpdateStatusChanged: (() -> Void)?

    private override init() {
        super.init()
    }

    func checkForUpdates(force: Bool = false) {
        // Get current app version
        let currentVersion = getCurrentAppVersion()
        writeLog("Current app version: \(currentVersion)")

        // Check if we need to check for updates based on last check date
        let lastCheckDate = UserDefaults.standard.object(forKey: userDefaultsLastCheckKey) as? Date
        let calendar = Calendar.current
        let now = Date()

        // Only check once per day unless forced
        if !force, let lastCheck = lastCheckDate, calendar.isDateInToday(lastCheck) {
            writeLog("Already checked for updates today. Skipping.")
            return
        }

        // Update the last check date
        UserDefaults.standard.set(now, forKey: userDefaultsLastCheckKey)

        // Start checking for updates
        isCheckingForUpdates = true
        onUpdateStatusChanged?()
        writeLog("Checking for updates...")

        // Create URL request
        guard let url = URL(string: updateInfoURL) else {
            writeLog("Invalid update URL")
            isCheckingForUpdates = false
            onUpdateStatusChanged?()
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            defer {
                self.isCheckingForUpdates = false
                DispatchQueue.main.async {
                    self.onUpdateStatusChanged?()
                }
            }

            if let error = error {
                writeLog("Error checking for updates: \(error.localizedDescription)")
                return
            }

            guard let data = data, let updateInfo = String(data: data, encoding: .utf8) else {
                writeLog("Could not parse update information")
                return
            }

            // Parse update info
            // Format is expected to be: URL filename version
            let components = updateInfo.trimmingCharacters(in: .whitespacesAndNewlines).components(
                separatedBy: " ")
            guard components.count >= 3 else {
                writeLog("Invalid update info format: \(updateInfo)")
                return
            }

            let newUpdateURL = components[0]
            let newFileName = components[1]
            let newVersion = components[2]

            writeLog(
                "Found update info - URL: \(newUpdateURL), Filename: \(newFileName), Version: \(newVersion)"
            )

            // Parse and compare semantic versions
            guard let currentSemVer = SemanticVersion(versionString: currentVersion),
                let newSemVer = SemanticVersion(versionString: newVersion)
            else {
                writeLog(
                    "Error: Invalid version format. Current: \(currentVersion), New: \(newVersion)")
                return
            }

            self.updateAvailable = newSemVer > currentSemVer
            self.latestVersion = newVersion
            self.updateURL = newUpdateURL
            self.updateFileName = newFileName

            if self.updateAvailable {
                writeLog("Update available: \(newVersion) (current: \(currentVersion))")
            } else {
                writeLog("No update available, current version (\(currentVersion)) is up to date")
            }
        }

        task.resume()
    }

    func downloadAndInstallUpdate() {
        guard updateAvailable, !updateURL.isEmpty else {
            writeLog("No update available to download")
            return
        }

        isDownloadingUpdate = true
        downloadProgress = 0.0
        onUpdateStatusChanged?()
        writeLog("Starting update download from \(updateURL)")

        // Handle Google Drive URLs
        var finalURL = updateURL
        if updateURL.contains("drive.google.com/file/d/") {
            // Extract the file ID and create a direct download URL
            if let fileID = extractGoogleDriveFileID(from: updateURL) {
                finalURL = "https://drive.google.com/uc?export=download&id=\(fileID)"
            }
        }

        guard let url = URL(string: finalURL) else {
            writeLog("Invalid download URL")
            isDownloadingUpdate = false
            onUpdateStatusChanged?()
            return
        }

        // Create download directory
        let fileManager = FileManager.default
        let downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let tempDirectory = downloadsDirectory.appendingPathComponent(
            "WhisperRecorderUpdate", isDirectory: true)

        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let destinationURL = tempDirectory.appendingPathComponent(updateFileName)

        // Remove existing file if it exists
        try? fileManager.removeItem(at: destinationURL)

        // Configure session
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        let downloadTask = session.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isDownloadingUpdate = false
                self.onUpdateStatusChanged?()

                if let error = error {
                    writeLog("Error downloading update: \(error.localizedDescription)")
                    return
                }

                guard let tempURL = tempURL else {
                    writeLog("No downloaded file URL")
                    return
                }

                // Create a local copy of the destination URL to avoid capturing fileManager
                let localDestinationURL = destinationURL

                // Use the dispatch queue to perform the file operations
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        // Create a local FileManager inside the closure
                        let localFileManager = FileManager.default

                        // Move file to destination
                        try localFileManager.moveItem(at: tempURL, to: localDestinationURL)
                        writeLog("Update downloaded to \(localDestinationURL.path)")

                        // If it's a zip file, unzip it
                        if localDestinationURL.pathExtension.lowercased() == "zip" {
                            DispatchQueue.main.async {
                                self.unzipAndInstallUpdate(zipFile: localDestinationURL)
                            }
                        } else {
                            writeLog("Downloaded file is not a zip archive")
                        }
                    } catch {
                        writeLog("Error saving downloaded file: \(error.localizedDescription)")
                    }
                }
            }
        }

        downloadTask.resume()
    }

    private func unzipAndInstallUpdate(zipFile: URL) {
        writeLog("Unzipping update file: \(zipFile.path)")

        // Get the current app path
        let currentAppPath = Bundle.main.bundleURL.path
        writeLog("Current app path: \(currentAppPath)")

        // Create a temporary directory for unzipping
        let fileManager = FileManager.default
        let tempUnzipDirectory = zipFile.deletingLastPathComponent().appendingPathComponent(
            "Unzipped", isDirectory: true)

        try? fileManager.createDirectory(at: tempUnzipDirectory, withIntermediateDirectories: true)

        // Run unzip command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipFile.path, "-d", tempUnzipDirectory.path]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                writeLog("Successfully unzipped update file")

                // Find the .app file in the unzipped directory
                if let contents = try? fileManager.contentsOfDirectory(
                    at: tempUnzipDirectory, includingPropertiesForKeys: nil)
                {
                    let appFiles = contents.filter { $0.pathExtension.lowercased() == "app" }

                    if let appFile = appFiles.first {
                        writeLog("Found app file: \(appFile.path)")
                        installUpdate(from: appFile, currentAppPath: currentAppPath)
                    } else {
                        writeLog("No .app file found in the unzipped update")
                    }
                }
            } else {
                writeLog("Failed to unzip update file, status: \(process.terminationStatus)")
            }
        } catch {
            writeLog("Error running unzip: \(error.localizedDescription)")
        }
    }

    private func installUpdate(from newAppURL: URL, currentAppPath: String) {
        writeLog("Installing update from \(newAppURL.path) to \(currentAppPath)")

        // Save the new version number
        UserDefaults.standard.set(latestVersion, forKey: userDefaultsCurrentVersionKey)

        // Show an alert to the user
        let alert = NSAlert()
        alert.messageText = "WhisperRecorder Update"
        alert.informativeText =
            "An update has been downloaded. The application will now restart to complete the installation."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install and Restart")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // User clicked "Install and Restart"
            writeLog("User approved update installation")

            // Create a script to execute after app quits
            let fileManager = FileManager.default
            let tempDirectory = fileManager.temporaryDirectory
            let scriptPath = tempDirectory.appendingPathComponent("whisper_updater.sh")

            // The script will wait for the app to quit, then replace it, then relaunch
            let scriptContent = """
                #!/bin/bash
                # Wait for the app to quit
                sleep 2

                # Replace the app
                rm -rf "\(currentAppPath)"
                cp -R "\(newAppURL.path)" "\(currentAppPath)"

                # Launch the app
                open "\(currentAppPath)"

                # Clean up
                rm -f "$0"
                """

            do {
                try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

                // Run the script in the background
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [scriptPath.path]

                try process.run()

                // Quit the app
                writeLog("Quitting app for update installation")
                NSApplication.shared.terminate(nil)
            } catch {
                writeLog("Error creating update script: \(error.localizedDescription)")
            }
        } else {
            writeLog("User postponed update installation")
        }
    }

    private func getCurrentAppVersion() -> String {
        // Get version from user defaults if available
        if let savedVersion = UserDefaults.standard.string(forKey: userDefaultsCurrentVersionKey) {
            return savedVersion
        }

        // Otherwise use the bundle version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        // Save it for future reference
        UserDefaults.standard.set(version, forKey: userDefaultsCurrentVersionKey)

        return version
    }

    private func extractGoogleDriveFileID(from url: String) -> String? {
        // Regular pattern for Google Drive URLs
        // https://drive.google.com/file/d/{fileId}/view
        let pattern = "drive\\.google\\.com/file/d/([^/]+)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsString = url as NSString
        let results = regex.matches(
            in: url, options: [], range: NSRange(location: 0, length: nsString.length))

        if let match = results.first, match.numberOfRanges > 1 {
            return nsString.substring(with: match.range(at: 1))
        }

        return nil
    }
}

// Extension to make AutoUpdater conform to URLSessionDownloadDelegate
extension AutoUpdater: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The completion handler in downloadAndInstallUpdate will handle this
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.downloadProgress = progress
                self.onUpdateStatusChanged?()
            }
        }
    }
}

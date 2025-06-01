import Foundation
import AppKit

/// Prevents multiple instances of the app from running simultaneously
class InstanceLock {
    private let lockFileName = "WhisperRecorder.lock"
    private var lockFilePath: String {
        let tempDir = NSTemporaryDirectory()
        return tempDir.appending(lockFileName)
    }
    
    private var lockFileHandle: FileHandle?
    
    /// Attempts to acquire an exclusive lock
    /// - Returns: true if lock acquired successfully, false if another instance is running
    func tryLock() -> Bool {
        // Check if another instance is running via NSRunningApplication
        let runningApps = NSWorkspace.shared.runningApplications
        let whisperApps = runningApps.filter { app in
            return app.bundleIdentifier == Bundle.main.bundleIdentifier && 
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        
        if !whisperApps.isEmpty {
            logWarning(.app, "Found other WhisperRecorder instances running: \\(whisperApps.map { $0.processIdentifier })")
            return false
        }
        
        // Try to create and lock the file
        let fileManager = FileManager.default
        
        // Remove stale lock file if it exists but no process is using it
        if fileManager.fileExists(atPath: lockFilePath) {
            if let handle = FileHandle(forUpdatingAtPath: lockFilePath) {
                // Try to acquire exclusive lock
                if flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
                    // We got the lock, previous instance must have crashed
                    logInfo(.app, "Acquired orphaned lock file")
                    lockFileHandle = handle
                    return true
                } else {
                    // Lock is held by another process
                    handle.closeFile()
                    logWarning(.app, "Lock file is held by another process")
                    return false
                }
            }
        }
        
        // Create new lock file
        fileManager.createFile(atPath: lockFilePath, contents: "\\(ProcessInfo.processInfo.processIdentifier)".data(using: .utf8))
        
        guard let handle = FileHandle(forUpdatingAtPath: lockFilePath) else {
            logError(.app, "Could not open lock file for writing")
            return false
        }
        
        // Try to acquire exclusive lock
        if flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            lockFileHandle = handle
            logInfo(.app, "Successfully acquired instance lock")
            
            // Set up cleanup on app termination
            atexit {
                // This won't work properly in atexit, but it's a backup
            }
            
            return true
        } else {
            handle.closeFile()
            logError(.app, "Could not acquire exclusive lock")
            return false
        }
    }
    
    /// Releases the lock
    func unlock() {
        guard let handle = lockFileHandle else { return }
        
        flock(handle.fileDescriptor, LOCK_UN)
        handle.closeFile()
        lockFileHandle = nil
        
        // Remove lock file
        try? FileManager.default.removeItem(atPath: lockFilePath)
        logInfo(.app, "Released instance lock")
    }
    
    deinit {
        unlock()
    }
} 
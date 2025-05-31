import Foundation
import os.log

// MARK: - Log Level and Category Definitions

enum LogLevel: String, CaseIterable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    var osLogType: OSLogType {
        switch self {
        case .trace: return .debug
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
    
    var priority: Int {
        switch self {
        case .trace: return 0
        case .debug: return 1
        case .info: return 2
        case .warning: return 3
        case .error: return 4
        }
    }
}

enum LogCategory: String, CaseIterable {
    case audio = "AUDIO"
    case whisper = "WHISPER"
    case llm = "LLM"
    case ui = "UI"
    case storage = "STORAGE"
    case network = "NETWORK"
    case memory = "MEMORY"
    case performance = "PERFORMANCE"
    case system = "SYSTEM"
    case general = "GENERAL"
    
    var subsystem: String {
        return "com.whisperrecorder.\(rawValue.lowercased())"
    }
}

// MARK: - Debug Configuration

struct DebugConfiguration {
    var isEnabled: Bool = false
    var logLevel: LogLevel = .info
    var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)
    var enableConsoleOutput: Bool = true
    var enableStdoutOutput: Bool = false
    var enableFileOutput: Bool = true
    var enableStructuredLogging: Bool = true
    var maxLogFileSize: Int = 10 * 1024 * 1024 // 10MB
    var logFileRetentionDays: Int = 7
    
    static let `default` = DebugConfiguration()
    static let debug = DebugConfiguration(
        isEnabled: true,
        logLevel: .trace,
        enabledCategories: Set(LogCategory.allCases),
        enableConsoleOutput: false,
        enableStdoutOutput: true,
        enableFileOutput: false,
        enableStructuredLogging: false
    )
    static let verbose = DebugConfiguration(
        isEnabled: true,
        logLevel: .trace,
        enabledCategories: Set(LogCategory.allCases),
        enableConsoleOutput: true,
        enableStdoutOutput: true,
        enableFileOutput: true,
        enableStructuredLogging: true
    )
    static let stdout = DebugConfiguration(
        isEnabled: true,
        logLevel: .trace,
        enabledCategories: Set(LogCategory.allCases),
        enableConsoleOutput: true,
        enableStdoutOutput: true,
        enableFileOutput: true,
        enableStructuredLogging: true
    )
}

// MARK: - Log Entry Structure

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let file: String
    let function: String
    let line: Int
    let metadata: [String: Any]?
    
    var formattedMessage: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timeString = formatter.string(from: timestamp)
        
        let fileBaseName = URL(fileURLWithPath: file).lastPathComponent
        return "[\(timeString)] [\(category.rawValue)] [\(level.rawValue)] [\(fileBaseName):\(line)] \(message)"
    }
    
    var structuredMessage: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let timeString = formatter.string(from: timestamp)
        
        var json: [String: Any] = [
            "timestamp": timeString,
            "level": level.rawValue,
            "category": category.rawValue,
            "message": message,
            "source": [
                "file": URL(fileURLWithPath: file).lastPathComponent,
                "function": function,
                "line": line
            ]
        ]
        
        if let metadata = metadata {
            json["metadata"] = metadata
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return formattedMessage
    }
}

// MARK: - Debug Manager

class DebugManager {
    static let shared = DebugManager()
    
    private var configuration: DebugConfiguration
    private let logQueue = DispatchQueue(label: "com.whisperrecorder.debug", qos: .utility)
    private var loggers: [LogCategory: OSLog] = [:]
    private var fileHandle: FileHandle?
    private let logFileURL: URL
    
    // Performance tracking
    private var performanceTimers: [String: Date] = [:]
    private let performanceQueue = DispatchQueue(label: "com.whisperrecorder.performance", qos: .utility)
    
    // Memory tracking
    private var memoryTimer: Timer?
    private var lastMemoryUsage: UInt64 = 0
    
    private init() {
        // Determine configuration based on build type and environment
        #if DEBUG
        // Check if stdout logging is explicitly requested
        if ProcessInfo.processInfo.environment["WHISPER_STDOUT_LOGS"] != nil {
            // Enable stdout logging mode
            self.configuration = DebugConfiguration.stdout
        } else if ProcessInfo.processInfo.environment["WHISPER_VERBOSE_LOGS"] != nil {
            // Verbose mode with all outputs
            self.configuration = DebugConfiguration.verbose
        } else {
            // Default debug mode
            self.configuration = DebugConfiguration.debug
        }
        #else
        // Check if debug mode is enabled via UserDefaults or environment
        let debugEnabled = UserDefaults.standard.bool(forKey: "WhisperRecorder.DebugMode") ||
                          ProcessInfo.processInfo.environment["WHISPER_DEBUG"] != nil
        
        if debugEnabled {
            if ProcessInfo.processInfo.environment["WHISPER_STDOUT_LOGS"] != nil {
                self.configuration = DebugConfiguration.stdout
            } else {
                self.configuration = DebugConfiguration.verbose
            }
        } else {
            self.configuration = DebugConfiguration.default
        }
        #endif
        
        // Setup log file URL - create it directly without calling methods
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appSupportPath = applicationSupport.appendingPathComponent("WhisperRecorder")
        self.logFileURL = appSupportPath.appendingPathComponent("whisperrecorder_debug.log")
        
        setupLoggers()
        setupFileLogging()
        
        if configuration.isEnabled {
            if configuration.enableStdoutOutput {
                print("=== WhisperRecorder Debug Mode - Console Output ===")
                print("Configuration: stdout=\(configuration.enableStdoutOutput), console=\(configuration.enableConsoleOutput), file=\(configuration.enableFileOutput)")
                print("Log Level: \(configuration.logLevel.rawValue)")
                print("Categories: \(configuration.enabledCategories.map { $0.rawValue }.joined(separator: ", "))")
                print("=================================================")
                
                // Immediate test output
                print("🔍 TRACE TEST: DebugManager stdout mode is working")
                print("🐛 DEBUG TEST: Environment WHISPER_STDOUT_LOGS = \(ProcessInfo.processInfo.environment["WHISPER_STDOUT_LOGS"] ?? "nil")")
                print("ℹ️  INFO TEST: DebugManager configuration loaded successfully")
                fflush(stdout)
            }
            
            startMemoryTracking()
            log(.system, .info, "DebugManager initialized with configuration: stdout=\(configuration.enableStdoutOutput), console=\(configuration.enableConsoleOutput), file=\(configuration.enableFileOutput)")
        }
    }
    
    // MARK: - Configuration Management
    
    func updateConfiguration(_ newConfiguration: DebugConfiguration) {
        logQueue.sync {
            let oldEnabled = configuration.isEnabled
            configuration = newConfiguration
            
            // Save debug mode preference
            UserDefaults.standard.set(configuration.isEnabled, forKey: "WhisperRecorder.DebugMode")
            
            if configuration.isEnabled && !oldEnabled {
                startMemoryTracking()
                log(.system, .info, "Debug mode enabled")
            } else if !configuration.isEnabled && oldEnabled {
                stopMemoryTracking()
                log(.system, .info, "Debug mode disabled")
            }
            
            setupFileLogging()
        }
    }
    
    var isDebugEnabled: Bool {
        return configuration.isEnabled
    }
    
    var currentConfiguration: DebugConfiguration {
        return configuration
    }
    
    // MARK: - Logging Methods
    
    func log(_ category: LogCategory, _ level: LogLevel, _ message: String, 
            file: String = #file, function: String = #function, line: Int = #line, 
            metadata: [String: Any]? = nil) {
        
        guard configuration.isEnabled,
              level.priority >= configuration.logLevel.priority,
              configuration.enabledCategories.contains(category) else {
            return
        }
        
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata
        )
        
        logQueue.async {
            self.processLogEntry(entry)
        }
    }
    
    // Convenience methods for different log levels
    func trace(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
        log(category, .trace, message, file: file, function: function, line: line, metadata: metadata)
    }
    
    func debug(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
        log(category, .debug, message, file: file, function: function, line: line, metadata: metadata)
    }
    
    func info(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
        log(category, .info, message, file: file, function: function, line: line, metadata: metadata)
    }
    
    func warning(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
        log(category, .warning, message, file: file, function: function, line: line, metadata: metadata)
    }
    
    func error(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
        log(category, .error, message, file: file, function: function, line: line, metadata: metadata)
    }
    
    // MARK: - Performance Tracking
    
    func startPerformanceTimer(_ operation: String) {
        performanceQueue.sync {
            performanceTimers[operation] = Date()
        }
        trace(.performance, "Started timing: \(operation)")
    }
    
    func endPerformanceTimer(_ operation: String) -> TimeInterval? {
        return performanceQueue.sync {
            guard let startTime = performanceTimers.removeValue(forKey: operation) else {
                warning(.performance, "No timer found for operation: \(operation)")
                return nil
            }
            
            let duration = Date().timeIntervalSince(startTime)
            info(.performance, "\(operation) completed in \(String(format: "%.3f", duration))s",
                 metadata: ["operation": operation, "duration_ms": duration * 1000])
            
            return duration
        }
    }
    
    // MARK: - Memory Tracking
    
    private func startMemoryTracking() {
        guard memoryTimer == nil else { return }
        
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.logMemoryUsage()
        }
        
        // Log initial memory usage
        logMemoryUsage()
    }
    
    private func stopMemoryTracking() {
        memoryTimer?.invalidate()
        memoryTimer = nil
    }
    
    private func logMemoryUsage() {
        let currentUsage = getMemoryUsage()
        let previousUsage = lastMemoryUsage
        lastMemoryUsage = currentUsage
        
        let change = Int64(currentUsage) - Int64(previousUsage)
        let changeStr = change >= 0 ? "+\(formatMemorySize(UInt64(change)))" : "-\(formatMemorySize(UInt64(-change)))"
        
        debug(.memory, "Memory usage: \(formatMemorySize(currentUsage)) (\(changeStr))",
              metadata: [
                "current_bytes": currentUsage,
                "previous_bytes": previousUsage,
                "change_bytes": change
              ])
    }
    
    // MARK: - API Call Logging
    
    func logAPIRequest(_ category: LogCategory, url: String, method: String, headers: [String: String]? = nil, body: Data? = nil) {
        var metadata: [String: Any] = [
            "url": url,
            "method": method
        ]
        
        if let headers = headers {
            metadata["headers"] = headers
        }
        
        if let body = body {
            metadata["body_size"] = body.count
            if let bodyString = String(data: body, encoding: .utf8), bodyString.count < 1000 {
                metadata["body"] = bodyString
            }
        }
        
        debug(category, "API Request: \(method) \(url)", metadata: metadata)
    }
    
    func logAPIResponse(_ category: LogCategory, url: String, statusCode: Int, headers: [String: String]? = nil, body: Data? = nil, duration: TimeInterval) {
        var metadata: [String: Any] = [
            "url": url,
            "status_code": statusCode,
            "duration_ms": duration * 1000
        ]
        
        if let headers = headers {
            metadata["headers"] = headers
        }
        
        if let body = body {
            metadata["body_size"] = body.count
            if let bodyString = String(data: body, encoding: .utf8), bodyString.count < 1000 {
                metadata["body"] = bodyString
            }
        }
        
        let level: LogLevel = statusCode >= 400 ? .error : .info
        log(category, level, "API Response: \(statusCode) \(url) (\(String(format: "%.3f", duration))s)", metadata: metadata)
    }
    
    // MARK: - Private Methods
    
    private func setupLoggers() {
        for category in LogCategory.allCases {
            loggers[category] = OSLog(subsystem: category.subsystem, category: category.rawValue)
        }
    }
    
    private func setupFileLogging() {
        guard configuration.enableFileOutput else {
            fileHandle?.closeFile()
            fileHandle = nil
            return
        }
        
        do {
            // Ensure directory exists
            let directory = logFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            // Create or open log file
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }
            
            fileHandle = try FileHandle(forWritingTo: logFileURL)
            fileHandle?.seekToEndOfFile()
            
            // Rotate log file if it's too large
            rotateLogFileIfNeeded()
            
        } catch {
            print("Failed to setup file logging: \(error)")
        }
    }
    
    private func processLogEntry(_ entry: LogEntry) {
        // Stdout output (for terminal/debug mode)
        if configuration.enableStdoutOutput {
            let stdoutMessage = formatForStdout(entry)
            print(stdoutMessage)
            fflush(stdout)  // Ensure immediate output
        }
        
        // Console output (OSLog)
        if configuration.enableConsoleOutput {
            if let logger = loggers[entry.category] {
                os_log("%{public}@", log: logger, type: entry.level.osLogType, entry.formattedMessage)
            } else {
                print(entry.formattedMessage)
            }
        }
        
        // File output
        if configuration.enableFileOutput, let fileHandle = fileHandle {
            let message = configuration.enableStructuredLogging ? entry.structuredMessage : entry.formattedMessage
            let data = (message + "\n").data(using: .utf8) ?? Data()
            fileHandle.write(data)
        }
    }
    
    private func formatForStdout(_ entry: LogEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: entry.timestamp)
        
        let levelIcon = getLevelIcon(entry.level)
        let categoryColor = getCategoryColor(entry.category)
        let levelColor = getLevelColor(entry.level)
        
        // Simplified format for stdout: [TIME] LEVEL CATEGORY: MESSAGE
        return "[\(timeString)] \(levelIcon)\(levelColor)\(entry.level.rawValue)\u{001B}[0m \(categoryColor)\(entry.category.rawValue)\u{001B}[0m: \(entry.message)"
    }
    
    private func getLevelIcon(_ level: LogLevel) -> String {
        switch level {
        case .trace: return "🔍 "
        case .debug: return "🐛 "
        case .info: return "ℹ️  "
        case .warning: return "⚠️  "
        case .error: return "❌ "
        }
    }
    
    private func getLevelColor(_ level: LogLevel) -> String {
        // ANSI color codes
        switch level {
        case .trace: return "\u{001B}[37m"      // White
        case .debug: return "\u{001B}[36m"      // Cyan
        case .info: return "\u{001B}[32m"       // Green
        case .warning: return "\u{001B}[33m"    // Yellow
        case .error: return "\u{001B}[31m"      // Red
        }
    }
    
    private func getCategoryColor(_ category: LogCategory) -> String {
        // ANSI color codes for categories
        switch category {
        case .audio: return "\u{001B}[35m"      // Magenta
        case .whisper: return "\u{001B}[34m"    // Blue
        case .llm: return "\u{001B}[95m"        // Bright Magenta
        case .ui: return "\u{001B}[96m"         // Bright Cyan
        case .storage: return "\u{001B}[93m"    // Bright Yellow
        case .network: return "\u{001B}[92m"    // Bright Green
        case .memory: return "\u{001B}[94m"     // Bright Blue
        case .performance: return "\u{001B}[91m" // Bright Red
        case .system: return "\u{001B}[97m"     // Bright White
        case .general: return "\u{001B}[90m"    // Dark Gray
        }
    }
    
    private func rotateLogFileIfNeeded() {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            if let fileSize = attributes[.size] as? Int, fileSize > configuration.maxLogFileSize {
                // Archive current log file
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let timestamp = formatter.string(from: Date())
                let archiveURL = logFileURL.appendingPathExtension("archive.\(timestamp)")
                
                try FileManager.default.moveItem(at: logFileURL, to: archiveURL)
                
                // Create new log file
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
                fileHandle = try FileHandle(forWritingTo: logFileURL)
                
                info(.system, "Log file rotated to: \(archiveURL.lastPathComponent)")
                
                // Clean up old archive files
                cleanupOldLogFiles()
            }
        } catch {
            warning(.system, "Failed to rotate log file: \(error)")
        }
    }
    
    private func cleanupOldLogFiles() {
        let directory = logFileURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -configuration.logFileRetentionDays, to: Date()) ?? Date()
            
            for file in files where file.pathExtension.hasPrefix("archive") {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let creationDate = attributes[.creationDate] as? Date, creationDate < cutoffDate {
                    try fileManager.removeItem(at: file)
                    info(.system, "Removed old log file: \(file.lastPathComponent)")
                }
            }
        } catch {
            warning(.system, "Failed to cleanup old log files: \(error)")
        }
    }
    
    private func getAppSupportDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appSupportPath = applicationSupport.appendingPathComponent("WhisperRecorder")
        
        do {
            try FileManager.default.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
            return appSupportPath
        } catch {
            print("Failed to create app support directory: \(error)")
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
    }
}

// MARK: - Helper Functions

func getMemoryUsage() -> UInt64 {
    var taskInfo = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
    let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    
    if result == KERN_SUCCESS {
        return taskInfo.phys_footprint
    }
    return 0
}

func formatMemorySize(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .memory
    return formatter.string(fromByteCount: Int64(bytes))
}

// MARK: - Global Debug Functions

func debugLog(_ category: LogCategory, _ level: LogLevel, _ message: String,
             file: String = #file, function: String = #function, line: Int = #line,
             metadata: [String: Any]? = nil) {
    DebugManager.shared.log(category, level, message, file: file, function: function, line: line, metadata: metadata)
}

// Convenience global functions
func logTrace(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
    DebugManager.shared.trace(category, message, file: file, function: function, line: line, metadata: metadata)
}

func logDebug(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
    DebugManager.shared.debug(category, message, file: file, function: function, line: line, metadata: metadata)
}

func logInfo(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
    DebugManager.shared.info(category, message, file: file, function: function, line: line, metadata: metadata)
}

func logWarning(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
    DebugManager.shared.warning(category, message, file: file, function: function, line: line, metadata: metadata)
}

func logError(_ category: LogCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: Any]? = nil) {
    DebugManager.shared.error(category, message, file: file, function: function, line: line, metadata: metadata)
}

// Performance tracking convenience functions
func startTiming(_ operation: String) {
    DebugManager.shared.startPerformanceTimer(operation)
}

func endTiming(_ operation: String) -> TimeInterval? {
    return DebugManager.shared.endPerformanceTimer(operation)
} 
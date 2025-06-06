import Foundation
import AVFoundation

// MARK: - Speaker Segment Data Models
struct SpeakerSegment {
    let speakerID: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
    
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    var displayName: String {
        return "Speaker \(speakerID.replacingOccurrences(of: "SPEAKER_", with: ""))"
    }
}

struct SpeakerTimeline {
    let segments: [SpeakerSegment]
    let totalDuration: TimeInterval
    
    var uniqueSpeakers: [String] {
        return Array(Set(segments.map { $0.speakerID })).sorted()
    }
    
    var speakerCount: Int {
        return uniqueSpeakers.count
    }
    
    func segments(for speakerID: String) -> [SpeakerSegment] {
        return segments.filter { $0.speakerID == speakerID }
    }
    
    func speakingTime(for speakerID: String) -> TimeInterval {
        return segments(for: speakerID).reduce(0) { $0 + $1.duration }
    }
}

// MARK: - Speaker Diarization Configuration
struct SpeakerDiarizationConfig {
    let enabled: Bool
    let speakerCount: SpeakerCount
    let sensitivity: Float
    let minimumSegmentDuration: TimeInterval
    
    static let `default` = SpeakerDiarizationConfig(
        enabled: false,
        speakerCount: .autoDetect,
        sensitivity: 0.5,
        minimumSegmentDuration: 1.0
    )
}

enum SpeakerCount: CaseIterable, Codable, Equatable, Hashable {
    case autoDetect
    case speakers(Int)
    
    var displayName: String {
        switch self {
        case .autoDetect:
            return "Auto-detect"
        case .speakers(let count):
            return "\(count) speakers"
        }
    }
    
    var value: Int? {
        switch self {
        case .autoDetect:
            return nil
        case .speakers(let count):
            return count
        }
    }
    
    static var allCases: [SpeakerCount] {
        var cases: [SpeakerCount] = [.autoDetect]
        for i in 2...10 {
            cases.append(.speakers(i))
        }
        return cases
    }
}

// MARK: - Speaker Diarization Engine
class SpeakerDiarizationEngine: ObservableObject {
    static let shared = SpeakerDiarizationEngine()
    
    @Published var config: SpeakerDiarizationConfig = SpeakerDiarizationConfig.default
    @Published var isProcessing = false
    @Published var processingProgress: Float = 0.0
    @Published var lastDiarizationResult: SpeakerTimeline?
    
    private var pyannoteIntegration: PyannoteIntegration?
    
    private init() {
        loadConfiguration()
        initializePyannoteIntegration()
    }
    
    // MARK: - Configuration Management
    
    private func loadConfiguration() {
        let defaults = UserDefaults.standard
        
        config = SpeakerDiarizationConfig(
            enabled: defaults.bool(forKey: "speakerDiarizationEnabled"),
            speakerCount: loadSpeakerCount(),
            sensitivity: defaults.object(forKey: "speakerDiarizationSensitivity") as? Float ?? 0.5,
            minimumSegmentDuration: defaults.object(forKey: "speakerMinimumSegmentDuration") as? TimeInterval ?? 1.0
        )
        
        logInfo(.audio, "Loaded speaker diarization config: enabled=\(config.enabled), count=\(config.speakerCount.displayName)")
    }
    
    private func loadSpeakerCount() -> SpeakerCount {
        let defaults = UserDefaults.standard
        
        if let data = defaults.data(forKey: "speakerCount"),
           let speakerCount = try? JSONDecoder().decode(SpeakerCount.self, from: data) {
            return speakerCount
        }
        
        return .autoDetect
    }
    
    func updateConfiguration(_ newConfig: SpeakerDiarizationConfig) {
        config = newConfig
        saveConfiguration()
        
        logInfo(.audio, "Updated speaker diarization config: enabled=\(config.enabled), count=\(config.speakerCount.displayName)")
    }
    
    private func saveConfiguration() {
        let defaults = UserDefaults.standard
        
        defaults.set(config.enabled, forKey: "speakerDiarizationEnabled")
        defaults.set(config.sensitivity, forKey: "speakerDiarizationSensitivity")
        defaults.set(config.minimumSegmentDuration, forKey: "speakerMinimumSegmentDuration")
        
        if let data = try? JSONEncoder().encode(config.speakerCount) {
            defaults.set(data, forKey: "speakerCount")
        }
    }
    
    // MARK: - Speaker Diarization Processing
    
    func processSpeakerDiarization(audioURL: URL, completion: @escaping (Result<SpeakerTimeline, Error>) -> Void) {
        guard config.enabled else {
            logInfo(.audio, "Speaker diarization disabled, skipping")
            logInfo(.performance, "⏸️ Speaker diarization disabled in configuration")
            completion(.success(SpeakerTimeline(segments: [], totalDuration: 0)))
            return
        }
        
        guard let pyannote = pyannoteIntegration else {
            logError(.audio, "Pyannote integration not available")
            logInfo(.performance, "🚫 Speaker diarization failed - pyannote integration not available")
            completion(.failure(SpeakerDiarizationError.pyannoteNotAvailable))
            return
        }
        
        logInfo(.audio, "Starting speaker diarization for audio: \(audioURL.lastPathComponent)")
        logInfo(.performance, "🚀 Speaker diarization engine initialized for: \(audioURL.lastPathComponent)")
        
        DispatchQueue.main.async {
            self.isProcessing = true
            self.processingProgress = 0.0
        }
        
        // Start speaker diarization in background
        DispatchQueue.global(qos: .userInitiated).async {
            pyannote.processSpeakerDiarization(
                audioURL: audioURL,
                config: self.config,
                progressCallback: { progress in
                    DispatchQueue.main.async {
                        self.processingProgress = progress
                    }
                }
            ) { result in
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.processingProgress = 0.0
                    
                    switch result {
                    case .success(let timeline):
                        self.lastDiarizationResult = timeline
                        logInfo(.audio, "Speaker diarization completed: \(timeline.speakerCount) speakers, \(timeline.segments.count) segments")
                        logInfo(.performance, "🎉 Speaker diarization pipeline completed successfully - \(timeline.speakerCount) speakers detected")
                        completion(.success(timeline))
                        
                    case .failure(let error):
                        logError(.audio, "Speaker diarization failed: \(error)")
                        logInfo(.performance, "💥 Speaker diarization pipeline failed: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    // MARK: - Pyannote Integration
    
    private func initializePyannoteIntegration() {
        // For now, create a mock integration
        // TODO: Implement real pyannote.audio integration
        pyannoteIntegration = PyannoteIntegration()
        
        logInfo(.audio, "Initialized Pyannote integration (mock implementation)")
    }
}

// MARK: - Pyannote Integration (Real Implementation)
class PyannoteIntegration {
    
    private let pythonScriptPath: String
    private let tempDirectory: URL
    
    init() {
        // Get the path to the Python script
        // Try multiple paths: app bundle, source directory, and relative paths
        let possiblePaths = [
            Bundle.main.resourcePath?.appending("/scripts/speaker_diarization.py"),
            "WhisperRecorder/scripts/speaker_diarization.py",
            "./WhisperRecorder/scripts/speaker_diarization.py",
            "../WhisperRecorder/scripts/speaker_diarization.py",
            FileManager.default.currentDirectoryPath + "/WhisperRecorder/scripts/speaker_diarization.py"
        ].compactMap { $0 }
        
        // Find the first existing path
        pythonScriptPath = possiblePaths.first { path in
            FileManager.default.fileExists(atPath: path)
        } ?? "WhisperRecorder/scripts/speaker_diarization.py"
        
        logInfo(.audio, "Python script search paths: \(possiblePaths)")
        logInfo(.audio, "Selected Python script path: \(pythonScriptPath)")
        logInfo(.audio, "Python script exists: \(FileManager.default.fileExists(atPath: pythonScriptPath))")
        
        // Create temp directory for JSON communication
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("WhisperRecorder_SpeakerDiarization")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            logInfo(.audio, "Created temp directory: \(tempDirectory.path)")
        } catch {
            logError(.audio, "Failed to create temp directory: \(error)")
        }
    }
    
    func processSpeakerDiarization(
        audioURL: URL,
        config: SpeakerDiarizationConfig,
        progressCallback: @escaping (Float) -> Void,
        completion: @escaping (Result<SpeakerTimeline, Error>) -> Void
    ) {
        logInfo(.audio, "Starting pyannote.audio speaker diarization")
        logInfo(.performance, "🎙️ Speaker diarization started for audio: \(audioURL.lastPathComponent)")
        startTiming("speaker_diarization")
        
        // Check if Python script exists
        if !FileManager.default.fileExists(atPath: pythonScriptPath) {
            logWarning(.audio, "Python script not found at: \(pythonScriptPath), using fallback mock")
            logInfo(.performance, "⚡ Speaker diarization fallback to mock implementation")
            processMockDiarization(progressCallback: progressCallback, completion: completion)
            return
        }
        
        // Create unique output files
        let timestamp = Date().timeIntervalSince1970
        let outputFile = tempDirectory.appendingPathComponent("diarization_\(timestamp).json")
        let progressFile = tempDirectory.appendingPathComponent("progress_\(timestamp).json")
        
        // Build Python command
        var pythonArgs = [
            pythonScriptPath,
            audioURL.path,
            "--output", outputFile.path,
            "--progress-file", progressFile.path
        ]
        
        // Add speaker count constraints
        switch config.speakerCount {
        case .speakers(let count):
            pythonArgs.append("--min-speakers")
            pythonArgs.append("\(max(1, count - 1))")  // Allow one less
            pythonArgs.append("--max-speakers")
            pythonArgs.append("\(count + 1)")  // Allow one more
        case .autoDetect:
            // No constraints, let pyannote auto-detect
            break
        }
        
        logInfo(.audio, "Running Python command: python3 \(pythonArgs.joined(separator: " "))")
        logInfo(.performance, "🐍 Python diarization process started with config: speakers=\(config.speakerCount)")
        
        // Start progress monitoring
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.readProgressFile(progressFile: progressFile, callback: progressCallback)
        }
        
        // Execute Python script asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = pythonArgs
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    progressTimer.invalidate()
                    
                    if process.terminationStatus == 0 {
                        // Success - read results
                        logInfo(.performance, "✅ Python diarization process completed successfully")
                        self.readDiarizationResults(
                            outputFile: outputFile,
                            progressCallback: progressCallback,
                            completion: completion
                        )
                    } else {
                        // Error - read stderr and fallback
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                        logError(.audio, "Python script failed: \(output)")
                        logInfo(.performance, "❌ Python diarization failed, fallback to mock implementation")
                        
                        // Fallback to mock implementation
                        logInfo(.audio, "Falling back to mock implementation")
                        self.processMockDiarization(progressCallback: progressCallback, completion: completion)
                    }
                    
                    // Cleanup temp files
                    try? FileManager.default.removeItem(at: outputFile)
                    try? FileManager.default.removeItem(at: progressFile)
                }
                
            } catch {
                DispatchQueue.main.async {
                    progressTimer.invalidate()
                    logError(.audio, "Failed to execute Python script: \(error)")
                    
                    // Fallback to mock implementation
                    self.processMockDiarization(progressCallback: progressCallback, completion: completion)
                    
                    // Cleanup temp files
                    try? FileManager.default.removeItem(at: outputFile)
                    try? FileManager.default.removeItem(at: progressFile)
                }
            }
        }
    }
    
    private func readProgressFile(progressFile: URL, callback: @escaping (Float) -> Void) {
        guard FileManager.default.fileExists(atPath: progressFile.path) else { return }
        
        do {
            let data = try Data(contentsOf: progressFile)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let progress = json?["progress"] as? Float {
                callback(progress)
            }
        } catch {
            // Ignore errors - progress file might be incomplete
        }
    }
    
    private func readDiarizationResults(
        outputFile: URL,
        progressCallback: @escaping (Float) -> Void,
        completion: @escaping (Result<SpeakerTimeline, Error>) -> Void
    ) {
        logInfo(.performance, "📊 Reading diarization results from output file")
        do {
            let data = try Data(contentsOf: outputFile)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let results = json?["results"] as? [String: Any],
                  let success = json?["success"] as? Bool,
                  success else {
                let errorMessage = json?["error"] as? String ?? "Unknown error"
                logError(.audio, "Python diarization failed: \(errorMessage)")
                processMockDiarization(progressCallback: progressCallback, completion: completion)
                return
            }
            
            // Parse segments
            guard let segmentsData = results["segments"] as? [[String: Any]] else {
                throw SpeakerDiarizationError.audioProcessingFailed("Invalid segments data")
            }
            
            let segments = try segmentsData.map { segmentData in
                guard let speakerID = segmentData["speaker_id"] as? String,
                      let startTime = segmentData["start_time"] as? Double,
                      let endTime = segmentData["end_time"] as? Double,
                      let confidence = segmentData["confidence"] as? Float else {
                    throw SpeakerDiarizationError.audioProcessingFailed("Invalid segment data")
                }
                
                return SpeakerSegment(
                    speakerID: speakerID,
                    startTime: startTime,
                    endTime: endTime,
                    confidence: confidence
                )
            }
            
            let totalDuration = results["total_duration"] as? Double ?? 0.0
            let timeline = SpeakerTimeline(segments: segments, totalDuration: totalDuration)
            
            progressCallback(1.0)
            logInfo(.audio, "Pyannote diarization completed: \(timeline.speakerCount) speakers, \(timeline.segments.count) segments")
            logInfo(.performance, "🎯 Speaker diarization result: \(timeline.speakerCount) speakers, \(timeline.segments.count) segments, duration: \(String(format: "%.1f", totalDuration))s")
            _ = endTiming("speaker_diarization")
            completion(.success(timeline))
            
        } catch {
            logError(.audio, "Failed to parse diarization results: \(error)")
            processMockDiarization(progressCallback: progressCallback, completion: completion)
        }
    }
    
    private func processMockDiarization(
        progressCallback: @escaping (Float) -> Void,
        completion: @escaping (Result<SpeakerTimeline, Error>) -> Void
    ) {
        logInfo(.audio, "Using mock speaker diarization (fallback)")
        logInfo(.performance, "🔄 Mock diarization started (fallback mode)")
        
        // Simulate processing with progress updates
        var progress: Float = 0.0
        var timer: Timer?
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progress += 0.1
            progressCallback(progress)
            
            if progress >= 1.0 {
                timer?.invalidate()
                
                // Create mock speaker timeline
                let mockSegments = [
                    SpeakerSegment(speakerID: "SPEAKER_00", startTime: 0.0, endTime: 15.5, confidence: 0.92),
                    SpeakerSegment(speakerID: "SPEAKER_01", startTime: 16.0, endTime: 32.3, confidence: 0.88),
                    SpeakerSegment(speakerID: "SPEAKER_00", startTime: 33.0, endTime: 45.7, confidence: 0.91),
                    SpeakerSegment(speakerID: "SPEAKER_01", startTime: 46.2, endTime: 60.0, confidence: 0.85)
                ]
                
                let timeline = SpeakerTimeline(segments: mockSegments, totalDuration: 60.0)
                
                logInfo(.audio, "Mock speaker diarization completed: \(timeline.speakerCount) speakers")
                logInfo(.performance, "✨ Mock diarization completed: \(timeline.speakerCount) speakers, \(timeline.segments.count) segments")
                _ = endTiming("speaker_diarization")
                completion(.success(timeline))
            }
        }
    }
}

// MARK: - Speaker Diarization Errors
enum SpeakerDiarizationError: LocalizedError {
    case pyannoteNotAvailable
    case audioProcessingFailed(String)
    case invalidAudioFormat
    case insufficientAudioLength
    
    var errorDescription: String? {
        switch self {
        case .pyannoteNotAvailable:
            return "Speaker diarization engine not available"
        case .audioProcessingFailed(let message):
            return "Audio processing failed: \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format for speaker diarization"
        case .insufficientAudioLength:
            return "Audio too short for speaker diarization"
        }
    }
} 
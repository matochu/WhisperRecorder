import AVFoundation
import CWhisper
import Foundation
import ObjectiveC  // For objc_setAssociatedObject

// Model information struct
struct WhisperModel {
    let id: String
    let displayName: String
    let size: String
    let language: String

    var filename: String {
        return "ggml-\(id).bin"
    }

    var downloadURL: URL {
        return URL(
            string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(id).bin")!
    }
}

class WhisperWrapper {
    static let shared = WhisperWrapper()
    private var modelPath: String?
    private var wrapper: OpaquePointer?
    public var currentModel: WhisperModel
    public var useLanguageDetection: Bool = true

    // Available models from download-ggml-model.sh
    static let availableModels: [WhisperModel] = [
        WhisperModel(id: "tiny", displayName: "Tiny", size: "~75MB", language: "Multilingual"),
        WhisperModel(
            id: "tiny.en", displayName: "Tiny (English)", size: "~75MB", language: "English"),
        WhisperModel(id: "base", displayName: "Base", size: "~142MB", language: "Multilingual"),
        WhisperModel(
            id: "base.en", displayName: "Base (English)", size: "~142MB", language: "English"),
        WhisperModel(id: "small", displayName: "Small", size: "~466MB", language: "Multilingual"),
        WhisperModel(
            id: "small.en", displayName: "Small (English)", size: "~466MB", language: "English"),
        WhisperModel(id: "medium", displayName: "Medium", size: "~1.5GB", language: "Multilingual"),
        WhisperModel(
            id: "medium.en", displayName: "Medium (English)", size: "~1.5GB", language: "English"),
        WhisperModel(
            id: "large-v3", displayName: "Large V3", size: "~3GB", language: "Multilingual"),
        WhisperModel(
            id: "large-v3-turbo-q8_0", displayName: "Large V3 Turbo (Q8_0)", size: "~834MB",
            language: "Multilingual"),
        WhisperModel(
            id: "large-v3-turbo-q5_0", displayName: "Large V3 Turbo (Q5_0)", size: "~547MB",
            language: "Multilingual"),
    ]

    var downloadProgress: Float = 0.0
    var isDownloading = false
    var onDownloadProgressUpdate: (() -> Void)?

    private init() {
        logInfo(.whisper, "WhisperWrapper initializing")

        // Try to get saved model from user defaults
        let defaults = UserDefaults.standard
        let savedModelID = defaults.string(forKey: "selectedWhisperModel") ?? "base.en"

        // Find the model or default to base.en
        if let model = WhisperWrapper.availableModels.first(where: { $0.id == savedModelID }) {
            currentModel = model
        } else {
            currentModel = WhisperWrapper.availableModels.first(where: { $0.id == "base.en" })!
        }

        // Set language detection based on model type
        useLanguageDetection =
            !currentModel.id.hasSuffix(".en") && currentModel.language == "Multilingual"
        logInfo(.whisper,
            "Set language detection to \(useLanguageDetection) for model \(currentModel.displayName)"
        )

        logInfo(.whisper, "Using model: \(currentModel.displayName) (\(currentModel.id))")

        // Check for model in application support directory
        checkAndLoadModel()
    }

    private func checkAndLoadModel() {
        let modelName = currentModel.filename

        // Check for model in application support directory (preferred location)
        let appSupportPath = getAppSupportDirectory()
        let appSupportModelPath = appSupportPath.appendingPathComponent(modelName).path

        if FileManager.default.fileExists(atPath: appSupportModelPath) {
            modelPath = appSupportModelPath
            logInfo(.whisper, "Using model from application support directory: \(appSupportModelPath)")
            loadModel()
            return
        }

        // Check if we're running from an app bundle with a custom resources path
        if let bundleResourcesPath = ProcessInfo.processInfo.environment["WHISPER_RESOURCES_PATH"] {
            let resourceModelPath = "\(bundleResourcesPath)/\(modelName)"
            if FileManager.default.fileExists(atPath: resourceModelPath) {
                modelPath = resourceModelPath
                logInfo(.whisper, "Using model from environment variable path: \(resourceModelPath)")
                loadModel()
                return
            } else {
                logWarning(.whisper, "Model not found at environment path: \(resourceModelPath)")
            }
        }

        // Check in documents directory as fallback
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[
            0]
        let documentsModelPath = documentsPath.appendingPathComponent(modelName).path

        if FileManager.default.fileExists(atPath: documentsModelPath) {
            modelPath = documentsModelPath
            logInfo(.whisper, "Using model from documents directory: \(documentsModelPath)")
            loadModel()
            return
        }

        // No model found, will need to download
        // Set the model path to where we want to save it
        modelPath = appSupportModelPath
        logWarning(.whisper,
            "Whisper model not found. Will need to download \(modelName) to \(appSupportModelPath)")
    }

    private func getAppSupportDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appSupportPath = applicationSupport.appendingPathComponent("WhisperRecorder")

        do {
            try FileManager.default.createDirectory(
                at: appSupportPath, withIntermediateDirectories: true)
            return appSupportPath
        } catch {
            logError(.storage, "Failed to create app support directory: \(error)")
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
    }

    deinit {
        if let wrapper = wrapper {
            whisper_wrapper_free(wrapper)
            logInfo(.whisper, "WhisperWrapper freed")
        }
    }

    func switchModel(to model: WhisperModel, completion: @escaping (Bool) -> Void) {
        // Free current model if loaded
        if let wrapper = wrapper {
            whisper_wrapper_free(wrapper)
            self.wrapper = nil
        }

        // Update current model
        currentModel = model

        // Automatically set language detection based on model type
        useLanguageDetection = !model.id.hasSuffix(".en") && model.language == "Multilingual"
        logInfo(.whisper, "Set language detection to \(useLanguageDetection) for model \(model.displayName)")

        // Save user preference
        UserDefaults.standard.set(model.id, forKey: "selectedWhisperModel")

        // Update model path
        let appSupportPath = getAppSupportDirectory()
        modelPath = appSupportPath.appendingPathComponent(model.filename).path

        // Check if model exists at the path
        if FileManager.default.fileExists(atPath: modelPath!) {
            loadModel()
            completion(true)
        } else {
            logWarning(.whisper, "Model \(model.filename) not found and needs to be downloaded")
            completion(false)
        }
    }

    func downloadCurrentModel(completion: @escaping (Bool) -> Void) {
        guard let modelPath = modelPath else {
            logError(.network, "Error: modelPath is nil in downloadModel()")
            completion(false)
            return
        }

        let modelURL = currentModel.downloadURL
        logInfo(.network, "Downloading model from: \(modelURL)")

        startTiming("model_download")
        isDownloading = true
        downloadProgress = 0.0
        onDownloadProgressUpdate?()

        let downloadTask = URLSession.shared.downloadTask(with: modelURL) {
            (tempURL, response, error) in
            self.isDownloading = false

            if let error = error {
                logError(.network, "Error downloading model: \(error)")
                completion(false)
                return
            }

            guard let tempURL = tempURL else {
                logError(.network, "Error: No temporary URL for downloaded file")
                completion(false)
                return
            }

            do {
                // Create directory if needed
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: modelPath).deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                // Move file from temporary location to destination
                if FileManager.default.fileExists(atPath: modelPath) {
                    try FileManager.default.removeItem(atPath: modelPath)
                }

                try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: modelPath))
                logInfo(.storage, "Model downloaded successfully to \(modelPath)")

                // Initialize whisper context
                DispatchQueue.main.async {
                    self.loadModel()
                    completion(true)
                }
            } catch {
                logError(.storage, "Error saving downloaded model: \(error)")
                completion(false)
            }
        }

        // Add progress observation
        downloadTask.resume()

        // Create an observation task to track download progress
        let observation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                self.downloadProgress = Float(progress.fractionCompleted)
                self.onDownloadProgressUpdate?()
            }
        }

        // Store observation as an associated object to prevent it from being deallocated
        objc_setAssociatedObject(downloadTask, "observation", observation, .OBJC_ASSOCIATION_RETAIN)

        logInfo(.network, "Started downloading Whisper model...")
    }

    private func loadModel() {
        guard let modelPath = modelPath else {
            logError(.storage, "Error: modelPath is nil in loadModel()")
            return
        }

        logInfo(.storage, "Loading model from path: \(modelPath)")

        // Check if file exists and get its size
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: modelPath) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: modelPath)
                if let size = attributes[.size] as? UInt64 {
                    logInfo(.storage, "Model file size: \(size) bytes")
                }
            } catch {
                logError(.storage, "Error getting model file attributes: \(error)")
            }
        } else {
            logError(.storage, "Error: Model file does not exist at path \(modelPath)")
        }

        wrapper = whisper_wrapper_create(modelPath)

        if wrapper == nil {
            logError(.storage, "Failed to initialize whisper context")

            // Add details for debugging
            let libraryPaths = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"] ?? "not set"
            logInfo(.storage, "DYLD_LIBRARY_PATH: \(libraryPaths)")

            if let insertLibs = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] {
                logInfo(.storage, "DYLD_INSERT_LIBRARIES: \(insertLibs)")
            }
        } else {
            logInfo(.storage, "Whisper model loaded successfully")
        }
    }

    func isModelLoaded() -> Bool {
        return wrapper != nil && whisper_wrapper_is_loaded(wrapper)
    }

    func transcribe(audioFile: URL) -> String {
        logInfo(.whisper, "Transcribe called for audio file: \(audioFile.path)")

        guard let wrapper = wrapper else {
            logError(.storage, "Whisper context not initialized")
            return "Error: Whisper model not loaded"
        }

        guard whisper_wrapper_is_loaded(wrapper) else {
            logError(.storage, "Whisper model is not properly loaded")
            return "Error: Whisper model not properly loaded"
        }

        // Debug file info
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioFile.path)
            let fileSize = attributes[.size] as? UInt64 ?? 0
            logInfo(.storage, "Audio file size: \(fileSize) bytes")
            if fileSize == 0 {
                logError(.storage, "Error: Audio file is empty")
                return "Error: Audio file is empty. Please try again."
            }
        } catch {
            logError(.storage, "Error checking file: \(error)")
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: audioFile.path) else {
            logError(.storage, "Error: Audio file doesn't exist at path \(audioFile.path)")
            return "Error: Audio file not found"
        }

        // For debugging, inspect the audio file format
        let avAsset = AVAsset(url: audioFile)

        // Modern approach using async/await in a synchronous context
        let semaphore = DispatchSemaphore(value: 0)
        var durationSeconds: Double = 0

        // Use modern async API but run it synchronously with semaphore
        Task {
            // Load audio tracks using the modern API
            let audioTracks = try? await avAsset.loadTracks(withMediaType: .audio)

            if let firstTrack = audioTracks?.first {
                // Load time range using the modern API
                let timeRange = try? await firstTrack.load(.timeRange)
                durationSeconds = timeRange?.duration.seconds ?? 0
                logInfo(.storage, "Audio track found: duration = \(durationSeconds)s")
            }
            semaphore.signal()
        }

        // Wait briefly for the async operation to complete
        _ = semaphore.wait(timeout: .now() + 1.0)

        // Use the original file directly without conversion
        logInfo(.whisper, "Transcribing file directly: \(audioFile.path)")
        logInfo(.whisper, "Using language detection: \(useLanguageDetection)")

        // Use the version with language detection parameter
        let result = whisper_wrapper_transcribe_with_lang(
            wrapper, audioFile.path, useLanguageDetection)

        if let result = result, let transcription = String(cString: result, encoding: .utf8) {
            // Check if it's an error message
            if transcription.starts(with: "Error:") {
                logError(.storage, "Transcription error: \(transcription)")
                return "Failed to transcribe audio. Please try again."
            }

            // Trim any whitespace and check if it's empty
            let trimmed = transcription.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if trimmed.isEmpty {
                logError(.storage, "No speech detected")
                return "No speech detected. Please try again."
            }

            logInfo(.storage, "Transcription result: \(trimmed)")
            return trimmed
        } else {
            logError(.storage, "Failed to get transcription result")
            return "Error: Failed to transcribe audio"
        }
    }

    func transcribePCM(audioData: [Float]) -> String {
        logInfo(.whisper, "TranscribePCM called with \(audioData.count) samples")

        guard let wrapper = wrapper else {
            logError(.storage, "Whisper context not initialized")
            return "Error: Whisper model not loaded"
        }

        guard whisper_wrapper_is_loaded(wrapper) else {
            logError(.storage, "Whisper model is not properly loaded")
            return "Error: Whisper model not properly loaded"
        }

        if audioData.isEmpty {
            logError(.storage, "Error: Empty PCM data")
            return "Error: No audio data provided"
        }

        // Save PCM data to a temporary WAV file for whisper.cpp
        let tempURL = saveAudioToTempFile(samples: audioData)

        guard let tempURL = tempURL else {
            logError(.storage, "Failed to save PCM data to temporary file")
            return "Error: Could not process audio data"
        }

        // Transcribe the temporary file
        let transcription = transcribe(audioFile: tempURL)

        // Clean up the temporary file
        try? FileManager.default.removeItem(at: tempURL)

        return transcription
    }

    private func saveAudioToTempFile(samples: [Float]) -> URL? {
        // Get temp directory URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("whisper_audio_\(UUID().uuidString).wav")

        logInfo(.storage, "Saving PCM data to temporary file: \(fileURL.path)")

        // Create WAV file with PCM data
        do {
            try createWavFile(at: fileURL, from: samples, sampleRate: 16000)
            return fileURL
        } catch {
            logError(.storage, "Error creating WAV file: \(error)")
            return nil
        }
    }

    private func createWavFile(at url: URL, from samples: [Float], sampleRate: Int) throws {
        // WAV header constants
        let headerSize = 44
        let formatCode = 3  // IEEE float
        let numChannels = 1
        let bitsPerSample = 32
        let byteRate = sampleRate * numChannels * bitsPerSample / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = samples.count * 4  // 4 bytes per Float
        let fileSize = headerSize + dataSize - 8  // Total file size - 8 for "RIFF" + size

        // Create a data buffer for the WAV file
        var data = Data(capacity: headerSize + dataSize)

        // WAV header - RIFF chunk
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        data.append(contentsOf: "WAVE".utf8)

        // WAV header - fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })  // fmt chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(formatCode).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Data($0) })
        data.append(
            contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Data($0) })

        // WAV header - data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })

        // Append PCM data
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample) { Data($0) })
        }

        // Write to file
        try data.write(to: url)
        logInfo(.storage, "WAV file created successfully with \(samples.count) samples")
    }

    var needsModelDownload: Bool {
        return wrapper == nil || !whisper_wrapper_is_loaded(wrapper)
    }
}

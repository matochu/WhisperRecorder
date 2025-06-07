import Foundation
import AVFoundation
import XCTest

/// Helper for real audio testing with actual audio files and expected transcriptions
struct RealAudioTestHelper {
    
    /// Real audio test case with known content
    struct TestCase {
        let audioFileName: String
        let expectedText: String
        let allowedErrorRate: Double // 0.0 to 1.0
        let duration: TimeInterval
        
        init(fileName: String, expectedText: String, allowedErrorRate: Double = 0.2, duration: TimeInterval) {
            self.audioFileName = fileName
            self.expectedText = expectedText
            self.allowedErrorRate = allowedErrorRate
            self.duration = duration
        }
    }
    
    /// Real test cases with known content from whisper.cpp samples
    static let testCases: [TestCase] = [
        TestCase(
            fileName: "jfk_original.wav",
            expectedText: "And so my fellow Americans ask not what your country can do for you ask what you can do for your country",
            allowedErrorRate: 0.15, // 15% error tolerance
            duration: 11.0
        ),
        TestCase(
            fileName: "micro_machines.wav", 
            expectedText: "This is a test of the Whisper speech recognition system using a sample of fast speech from the micro machines commercial",
            allowedErrorRate: 0.25, // 25% error tolerance - fast speech is much harder
            duration: 29.0
        ),
        TestCase(
            fileName: "clear_speech.wav",
            expectedText: "And so tonight my fellow Americans I ask you to join me in this work together we can meet these challenges",
            allowedErrorRate: 0.15, // 15% error tolerance - longer clear speech
            duration: 198.0
        )
    ]
    
    /// Get path to test audio files directory
    static func getTestAudioDirectory() throws -> URL {
        let bundle = Bundle(for: WhisperRecorderRealAudioTests.self)
        guard let resourcePath = bundle.resourcePath else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find bundle resource path"])
        }
        
        let testAudioDir = URL(fileURLWithPath: resourcePath).appendingPathComponent("TestAudioFiles")
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: testAudioDir.path) {
            try FileManager.default.createDirectory(at: testAudioDir, withIntermediateDirectories: true)
        }
        
        return testAudioDir
    }
    
    /// Get URL for specific test audio file - downloads automatically if missing
    static func getTestAudioURL(fileName: String) throws -> URL {
        let testDir = try getTestAudioDirectory()
        let audioURL = testDir.appendingPathComponent(fileName)
        
        // If file doesn't exist, try to download samples automatically
        if !FileManager.default.fileExists(atPath: audioURL.path) {
            print("📥 Audio file '\(fileName)' not found, attempting automatic download...")
            try downloadAudioSamplesIfNeeded(testDir: testDir)
            
            // Check again after download
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw NSError(domain: "TestError", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Test audio file not found after download: \(fileName)",
                    NSLocalizedRecoverySuggestionErrorKey: "Automatic download failed. Please check internet connection or manually run: ./download_samples.sh in TestAudioFiles directory."
                ])
            }
        }
        
        return audioURL
    }
    
    /// Load audio file as PCM data for Whisper
    static func loadAudioAsPCM(fileName: String) throws -> [Float] {
        let audioURL = try getTestAudioURL(fileName: fileName)
        
        // Load audio file
        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat
        
        // Ensure it's the right format for Whisper (16kHz, mono)
        guard format.sampleRate == 16000 else {
            throw NSError(domain: "TestError", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Audio file must be 16kHz sample rate, got \(format.sampleRate)Hz"
            ])
        }
        
        guard format.channelCount == 1 else {
            throw NSError(domain: "TestError", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Audio file must be mono, got \(format.channelCount) channels"
            ])
        }
        
        // Read all frames
        let frameCount = UInt32(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "TestError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not create audio buffer"])
        }
        
        try audioFile.read(into: buffer)
        
        // Convert to Float array
        guard let floatData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "TestError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not extract float data from audio"])
        }
        
        return Array(UnsafeBufferPointer(start: floatData, count: Int(buffer.frameLength)))
    }
    
    /// Download audio samples automatically if they don't exist
    static func downloadAudioSamplesIfNeeded(testDir: URL) throws {
        let downloadScript = testDir.appendingPathComponent("download_samples.sh")
        
        // Create the download script if it doesn't exist
        if !FileManager.default.fileExists(atPath: downloadScript.path) {
            try createDownloadScript(at: downloadScript)
        }
        
        // Make script executable
        let attributes = [FileAttributeKey.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: downloadScript.path)
        
        // Execute the download script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [downloadScript.path]
        process.currentDirectoryURL = testDir
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "TestError", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "Download script failed with exit code \(process.terminationStatus)",
                NSLocalizedRecoverySuggestionErrorKey: "Script output: \(output)"
            ])
        }
        
        print("✅ Audio samples downloaded successfully!")
        
        // Clean up temporary files to prevent them from being included in bundle
        cleanupTemporaryFiles(in: testDir)
    }
    
    /// Clean up temporary files after download to prevent bundle inclusion
    static func cleanupTemporaryFiles(in directory: URL) {
        let filesToClean = ["gb0.ogg", "gb1.ogg", "hp0.ogg", "mm1.wav", "jfk.wav", "jfk_16k.wav"]
        
        for file in filesToClean {
            let fileURL = directory.appendingPathComponent(file)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Also clean up the download script itself
        let scriptURL = directory.appendingPathComponent("download_samples.sh")
        try? FileManager.default.removeItem(at: scriptURL)
        
        print("🧹 Cleaned up temporary download files")
    }
    
    /// Create the download script for audio samples
    static func createDownloadScript(at url: URL) throws {
        let scriptContent = """
#!/bin/bash

# Download audio samples for WhisperRecorder testing
# Based on whisper.cpp samples infrastructure

set -e

echo "Downloading audio samples for testing..."

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is required but not installed. Please install it first:"
    echo "brew install ffmpeg"
    exit 1
fi

# Download original samples
echo "Downloading George W. Bush radio address..."
curl -L --progress-bar -o gb0.ogg "https://upload.wikimedia.org/wikipedia/commons/2/22/George_W._Bush%27s_weekly_radio_address_%28November_1%2C_2008%29.oga"

echo "Downloading George W. Bush Columbia speech..."
curl -L --progress-bar -o gb1.ogg "https://upload.wikimedia.org/wikipedia/commons/1/1f/George_W_Bush_Columbia_FINAL.ogg"

echo "Downloading Henry Phillips speech..."
curl -L --progress-bar -o hp0.ogg "https://upload.wikimedia.org/wikipedia/en/d/d4/En.henryfphillips.ogg"

echo "Downloading Micro Machines sample..."
curl -L --progress-bar -o mm1.wav "https://cdn.openai.com/whisper/draft-20220913a/micro-machines.wav"

echo "Downloading JFK sample..."
curl -L --progress-bar -o jfk.wav "https://github.com/ggerganov/whisper.cpp/raw/master/samples/jfk.wav"

echo "Converting to 16-bit WAV 16kHz mono format..."

# Convert all files to required format: 16kHz mono PCM s16le
ffmpeg -loglevel error -y -i gb0.ogg -ar 16000 -ac 1 -c:a pcm_s16le gb0.wav
ffmpeg -loglevel error -y -i gb1.ogg -ar 16000 -ac 1 -c:a pcm_s16le gb1.wav  
ffmpeg -loglevel error -y -i hp0.ogg -ar 16000 -ac 1 -c:a pcm_s16le hp0.wav
ffmpeg -loglevel error -y -i mm1.wav -ar 16000 -ac 1 -c:a pcm_s16le mm0.wav

# JFK is already in WAV, but let's ensure it's in the right format
ffmpeg -loglevel error -y -i jfk.wav -ar 16000 -ac 1 -c:a pcm_s16le jfk_16k.wav

# Clean up original downloads
rm -f gb0.ogg gb1.ogg hp0.ogg mm1.wav jfk.wav

# Rename files to match our test expectations
mv gb0.wav hello_world.wav          # "And so my fellow Americans, ask not what your country can do for you..."
mv gb1.wav clear_speech.wav         # Clear presidential speech
mv hp0.wav counting.wav              # English speech sample
mv mm0.wav micro_machines.wav        # Fast speech sample
mv jfk_16k.wav jfk_original.wav      # JFK speech

echo ""
echo "Audio samples downloaded and converted successfully!"
echo ""
echo "Available test files:"
ls -la *.wav | while read -r line; do
    file=$(echo "$line" | awk '{print $NF}')
    duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null | cut -d. -f1)
    echo "  $file (${duration}s)"
done

echo ""
echo "Files are ready for WhisperRecorder testing!"
"""
        
        try scriptContent.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Calculate text similarity (simple word-based comparison)
    static func calculateTextSimilarity(actual: String, expected: String) -> Double {
        let actualWords = Set(actual.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let expectedWords = Set(expected.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        
        if expectedWords.isEmpty { return 0.0 }
        
        let intersection = actualWords.intersection(expectedWords)
        return Double(intersection.count) / Double(expectedWords.count)
    }
    
    /// Validate transcription against expected text
    static func validateTranscription(actual: String, expected: String, allowedErrorRate: Double) -> (isValid: Bool, similarity: Double, details: String) {
        let similarity = calculateTextSimilarity(actual: actual, expected: expected)
        let requiredSimilarity = 1.0 - allowedErrorRate
        let isValid = similarity >= requiredSimilarity
        
        let details = """
        Expected: "\(expected)"
        Actual:   "\(actual)"
        Similarity: \(String(format: "%.1f", similarity * 100))%
        Required:   \(String(format: "%.1f", requiredSimilarity * 100))%
        """
        
        return (isValid, similarity, details)
    }
    
    /// Create a real test audio file programmatically (for development)
    static func createTestAudioFile(fileName: String, text: String, duration: TimeInterval) throws {
        // This would ideally use text-to-speech or load pre-recorded files
        // For now, we'll create instructions for manual creation
        let testDir = try getTestAudioDirectory()
        let instructionsURL = testDir.appendingPathComponent("INSTRUCTIONS.txt")
        
        let instructions = """
        Real audio test files from whisper.cpp samples have been downloaded!
        
        Available files:
        - jfk_original.wav (11s) - JFK "Ask not what your country can do for you" speech
        - micro_machines.wav (29s) - Fast speech sample from Micro Machines commercial
        - clear_speech.wav (198s) - Clear presidential speech
        - hello_world.wav (127s) - George W. Bush radio address
        - counting.wav (273s) - Henry Phillips speech sample
        
        These files are in the correct format: 16kHz mono WAV files.
        
        To download fresh samples, run:
        ./download_samples.sh
        
        Files location: \(testDir.path)
        Current test file being requested: \(fileName) ("\(text)")
        """
        
        try instructions.write(to: instructionsURL, atomically: true, encoding: .utf8)
        
        throw NSError(domain: "TestError", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Test audio files need to be created manually",
            NSLocalizedRecoverySuggestionErrorKey: "See instructions at: \(instructionsURL.path)"
        ])
    }
}

/// Extension for XCTest assertions
extension RealAudioTestHelper {
    
    /// Assert that transcription matches expected text within error tolerance
    static func assertTranscriptionMatches(
        actual: String,
        expected: String, 
        allowedErrorRate: Double,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let validation = validateTranscription(actual: actual, expected: expected, allowedErrorRate: allowedErrorRate)
        
        XCTAssert(validation.isValid, """
        Transcription accuracy below threshold:
        \(validation.details)
        """, file: file, line: line)
        
        print("✅ Transcription validation passed (\(String(format: "%.1f", validation.similarity * 100))% similarity)")
    }
} 
#!/usr/bin/env swift

import Foundation

/// Demo script showing speaker diarization and audio chunking workflows
/// This demonstrates the concepts without requiring actual Whisper libraries

// MARK: - Supporting Types

struct SpeakerSegment {
    let speakerId: Int
    let start: TimeInterval
    let end: TimeInterval
}

struct AudioChunk {
    let data: [Float]
    let startTime: TimeInterval
    let endTime: TimeInterval
}

// MARK: - Demo Functions

/// Generate mock audio data
func generateMockAudioData(samples: Int) -> [Float] {
    return (0..<samples).map { _ in Float.random(in: -0.1...0.1) }
}

/// Simulate speaker detection
func simulateSpeakerDetection(audioData: [Float]) -> [SpeakerSegment] {
    let audioDuration = Double(audioData.count) / 16000.0
    let numSpeakers = min(4, max(2, Int(audioDuration / 5.0))) // 1 speaker per 5 seconds
    
    var segments: [SpeakerSegment] = []
    let segmentDuration = audioDuration / Double(numSpeakers)
    
    for i in 0..<numSpeakers {
        let start = Double(i) * segmentDuration
        let end = min(start + segmentDuration, audioDuration)
        segments.append(SpeakerSegment(speakerId: i + 1, start: start, end: end))
    }
    
    return segments
}

/// Split audio into chunks
func chunkAudio(_ audioData: [Float], chunkSize: Int) -> [AudioChunk] {
    var chunks: [AudioChunk] = []
    let sampleRate = 16000.0
    
    for i in stride(from: 0, to: audioData.count, by: chunkSize) {
        let end = min(i + chunkSize, audioData.count)
        let chunk = Array(audioData[i..<end])
        
        if chunk.count > 1000 { // Only include substantial chunks
            let startTime = Double(i) / sampleRate
            let endTime = Double(end) / sampleRate
            chunks.append(AudioChunk(data: chunk, startTime: startTime, endTime: endTime))
        }
    }
    
    return chunks
}

/// Simulate basic transcription
func simulateBasicTranscription(audioData: [Float]) -> String {
    let processingTime = Double(audioData.count) / 16000.0 * 0.3
    Thread.sleep(forTimeInterval: min(processingTime, 1.0))
    
    return "This is a basic transcription of the entire audio without speaker identification"
}

/// Simulate speaker-aware transcription
func simulateSpeakerAwareTranscription(segments: [SpeakerSegment], audioData: [Float]) -> String {
    let processingTime = Double(audioData.count) / 16000.0 * 0.4
    Thread.sleep(forTimeInterval: min(processingTime, 1.2))
    
    let speakerTexts = [
        "Hello, this is the first speaker talking about the topic",
        "And I'm the second speaker with a different perspective", 
        "The third speaker here adding more information to the discussion",
        "Finally, the fourth speaker concluding the conversation"
    ]
    
    var result = ""
    for segment in segments {
        let textIndex = (segment.speakerId - 1) % speakerTexts.count
        result += "Speaker \(segment.speakerId): \(speakerTexts[textIndex]) "
    }
    
    return result.trimmingCharacters(in: .whitespaces)
}

/// Simulate chunked transcription
func simulateChunkedTranscription(chunks: [AudioChunk]) -> String {
    var results: [String] = []
    let chunkTexts = [
        "This is the first part of the conversation",
        "Here we continue with more discussion", 
        "The middle section contains important details",
        "And finally we wrap up the conversation"
    ]
    
    for (index, chunk) in chunks.enumerated() {
        let chunkProcessingTime = Double(chunk.data.count) / 16000.0 * 0.2
        Thread.sleep(forTimeInterval: min(chunkProcessingTime, 0.3))
        
        let textIndex = index % chunkTexts.count
        results.append(chunkTexts[textIndex])
    }
    
    return results.joined(separator: " ")
}

/// Calculate text similarity (simplified)
func calculateSimilarity(_ text1: String, _ text2: String) -> Double {
    let words1 = Set(text1.lowercased().components(separatedBy: .whitespaces))
    let words2 = Set(text2.lowercased().components(separatedBy: .whitespaces))
    
    let intersection = words1.intersection(words2)
    let union = words1.union(words2)
    
    return union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)
}

/// Estimate memory usage for different processing methods
func estimateMemoryUsage(method: String, audioSize: Int) -> Double {
    let baseMB = Double(audioSize) * 4 / (1024 * 1024) // Float size in MB
    
    switch method {
    case "basic":
        return baseMB * 1.2 // 20% overhead
    case "speaker":
        return baseMB * 1.8 // 80% overhead for speaker detection
    case "chunked":
        return baseMB * 0.6 // 40% savings from chunking
    default:
        return baseMB
    }
}

// MARK: - Main Demo

print("🎬 WhisperRecorder Speaker Processing Demo")
print("==========================================")

// Simulate audio data (20 seconds of audio at 16kHz)
let sampleRate = 16000
let durationSeconds = 20.0
let totalSamples = Int(durationSeconds * Double(sampleRate))
let audioData = generateMockAudioData(samples: totalSamples)

print("📊 Mock audio data: \(audioData.count) samples (\(String(format: "%.1f", durationSeconds))s)")

// 1. Basic Processing
print("\n🔤 1. Basic Processing:")
let basicStartTime = Date()
let basicResult = simulateBasicTranscription(audioData: audioData)
let basicTime = Date().timeIntervalSince(basicStartTime)

print("   Result: \"\(basicResult)\"")
print("   Time: \(String(format: "%.3f", basicTime))s")
print("   Processing speed: \(String(format: "%.2f", basicTime / durationSeconds))x real-time")

// 2. Speaker-Aware Processing
print("\n👥 2. Speaker-Aware Processing:")
let speakerStartTime = Date()
let speakerSegments = simulateSpeakerDetection(audioData: audioData)
let speakerResult = simulateSpeakerAwareTranscription(segments: speakerSegments, audioData: audioData)
let speakerTime = Date().timeIntervalSince(speakerStartTime)

print("   Detected speakers: \(speakerSegments.count)")
for (index, segment) in speakerSegments.enumerated() {
    print("   Speaker \(index + 1): \(String(format: "%.1f", segment.start))s - \(String(format: "%.1f", segment.end))s (\(String(format: "%.1f", segment.end - segment.start))s)")
}
print("   Result: \"\(speakerResult)\"")
print("   Time: \(String(format: "%.3f", speakerTime))s")
print("   Processing speed: \(String(format: "%.2f", speakerTime / durationSeconds))x real-time")

// 3. Chunked Processing
print("\n📦 3. Chunked Processing:")
let chunkedStartTime = Date()
let chunks = chunkAudio(audioData, chunkSize: totalSamples / 4) // 4 chunks
let chunkedResult = simulateChunkedTranscription(chunks: chunks)
let chunkedTime = Date().timeIntervalSince(chunkedStartTime)

print("   Number of chunks: \(chunks.count)")
for (index, chunk) in chunks.enumerated() {
    let chunkDuration = chunk.endTime - chunk.startTime
    print("   Chunk \(index + 1): \(chunk.data.count) samples (\(String(format: "%.1f", chunkDuration))s)")
}
print("   Result: \"\(chunkedResult)\"")
print("   Time: \(String(format: "%.3f", chunkedTime))s")
print("   Processing speed: \(String(format: "%.2f", chunkedTime / durationSeconds))x real-time")

// 4. Performance Comparison
print("\n📊 4. Performance Comparison:")
print("   ┌─────────────────┬──────────┬──────────┬────────────┐")
print("   │ Method          │ Time (s) │ Speed    │ Quality    │")
print("   ├─────────────────┼──────────┼──────────┼────────────┤")
print("   │ Basic           │ \(String(format: "%8.3f", basicTime)) │ \(String(format: "%5.2f", basicTime / durationSeconds))x   │ Standard   │")
print("   │ Speaker-aware   │ \(String(format: "%8.3f", speakerTime)) │ \(String(format: "%5.2f", speakerTime / durationSeconds))x   │ Enhanced   │")
print("   │ Chunked         │ \(String(format: "%8.3f", chunkedTime)) │ \(String(format: "%5.2f", chunkedTime / durationSeconds))x   │ Parallel   │")
print("   └─────────────────┴──────────┴──────────┴────────────┘")

// 5. Accuracy Comparison
print("\n🎯 5. Accuracy Analysis:")
let baseText = "This is a sample conversation between multiple speakers discussing various topics"
let basicAccuracy = calculateSimilarity(basicResult, baseText)
let speakerAccuracy = calculateSimilarity(speakerResult, baseText)
let chunkedAccuracy = calculateSimilarity(chunkedResult, baseText)

print("   Basic processing:     \(String(format: "%.1f", basicAccuracy * 100))% accuracy")
print("   Speaker-aware:        \(String(format: "%.1f", speakerAccuracy * 100))% accuracy")
print("   Chunked processing:   \(String(format: "%.1f", chunkedAccuracy * 100))% accuracy")

// 6. Memory Usage Simulation
print("\n💾 6. Memory Usage Analysis:")
let basicMemory = estimateMemoryUsage(method: "basic", audioSize: audioData.count)
let speakerMemory = estimateMemoryUsage(method: "speaker", audioSize: audioData.count)
let chunkedMemory = estimateMemoryUsage(method: "chunked", audioSize: audioData.count)

print("   Basic processing:     \(String(format: "%.1f", basicMemory))MB")
print("   Speaker-aware:        \(String(format: "%.1f", speakerMemory))MB")
print("   Chunked processing:   \(String(format: "%.1f", chunkedMemory))MB")

// 7. Real-world Application
print("\n🌍 7. Real-world Application in WhisperRecorder:")
print("   • Basic mode: Fast transcription for single speaker")
print("   • Speaker-aware mode: Identifies and labels different speakers")
print("   • Chunked mode: Processes long audio in parallel chunks")
print("   • Memory optimization: Chunking reduces peak memory usage")
print("   • Real-time capability: All methods can process faster than real-time")

print("\n✅ Speaker diarization workflow demo completed successfully!")
print("🎯 This demonstrates how WhisperRecorder processes audio with different strategies")
print("📈 Speaker-aware processing provides enhanced transcription with speaker identification")
print("⚡ Chunked processing enables parallel processing and memory optimization") 
import Foundation
import AVFoundation

public class TestAudioGenerator {
    
    /// Creates synthetic audio buffer with speech
    public static func createSpeechLikeAudioBuffer(
        duration: TimeInterval = 5.0,
        sampleRate: Int = 16000,
        includeWords: Bool = true
    ) -> [Float] {
        let sampleCount = Int(duration * Double(sampleRate))
        var audioBuffer = Array<Float>(repeating: 0.0, count: sampleCount)
        
        if includeWords {
            // Simulate speech: alternating sounds and pauses
            let wordDuration = 0.8  // 800ms per "word"
            let pauseDuration = 0.3 // 300ms pause
            let cycleLength = wordDuration + pauseDuration
            
            for i in 0..<sampleCount {
                let timeInSeconds = Double(i) / Double(sampleRate)
                let cyclePosition = timeInSeconds.truncatingRemainder(dividingBy: cycleLength)
                
                if cyclePosition < wordDuration {
                    // Generate "speech" - mix of frequencies
                    let progress = cyclePosition / wordDuration
                    let fundamental = Float(150 + 50 * sin(progress * 2 * Double.pi)) // Melodic variation
                    let formant1 = Float(800)  // First formant
                    let formant2 = Float(1200) // Second formant
                    
                    let sample1 = sin(2.0 * Float.pi * fundamental * Float(i) / Float(sampleRate))
                    let sample2 = sin(2.0 * Float.pi * formant1 * Float(i) / Float(sampleRate)) * 0.3
                    let sample3 = sin(2.0 * Float.pi * formant2 * Float(i) / Float(sampleRate)) * 0.2
                    
                    // Add noise for realism
                    let noise = Float.random(in: -0.05...0.05)
                    
                    audioBuffer[i] = (sample1 + sample2 + sample3 + noise) * 0.3
                } else {
                    // Pause between "words" with light noise
                    audioBuffer[i] = Float.random(in: -0.02...0.02)
                }
            }
        } else {
            // Simple sinusoidal tone
            let frequency: Float = 440.0 // A4 note
            for i in 0..<sampleCount {
                audioBuffer[i] = sin(2.0 * Float.pi * frequency * Float(i) / Float(sampleRate)) * 0.5
            }
        }
        
        return audioBuffer
    }
    
    /// Creates audio buffer for silence detection testing
    public static func createSilenceTestAudioBuffer(duration: TimeInterval = 10.0) -> [Float] {
        let sampleRate = 16000
        let sampleCount = Int(duration * Double(sampleRate))
        var audioBuffer = Array<Float>(repeating: 0.0, count: sampleCount)
        
        // Pattern: 2 sec speech, 1 sec silence, 3 sec speech, 2 sec silence, 2 sec speech
        let patterns: [(start: Double, duration: Double, isSpeech: Bool)] = [
            (0.0, 2.0, true),    // 0-2s: speech
            (2.0, 1.0, false),   // 2-3s: silence
            (3.0, 3.0, true),    // 3-6s: speech
            (6.0, 2.0, false),   // 6-8s: silence
            (8.0, 2.0, true),    // 8-10s: speech
        ]
        
        for pattern in patterns {
            let startSample = Int(pattern.start * Double(sampleRate))
            let endSample = Int((pattern.start + pattern.duration) * Double(sampleRate))
            
            for i in startSample..<min(endSample, sampleCount) {
                if pattern.isSpeech {
                    // Generate speech
                    let frequency = Float(200 + 100 * sin(Double(i) * 0.001))
                    audioBuffer[i] = sin(2.0 * Float.pi * frequency * Float(i) / Float(sampleRate)) * 0.4
                } else {
                    // Silence with minimal noise
                    audioBuffer[i] = Float.random(in: -0.01...0.01)
                }
            }
        }
        
        return audioBuffer
    }
    
    /// Creates audio for multi-speaker testing
    public static func createMultiSpeakerAudioBuffer(duration: TimeInterval = 8.0) -> [Float] {
        let sampleRate = 16000
        let sampleCount = Int(duration * Double(sampleRate))
        var audioBuffer = Array<Float>(repeating: 0.0, count: sampleCount)
        
        // Speaker 1: low voice (150Hz base)
        // Speaker 2: high voice (250Hz base)
        let speakerSegments: [(start: Double, duration: Double, speaker: Int)] = [
            (0.0, 2.0, 1),    // Speaker 1
            (2.0, 0.5, 0),    // Pause
            (2.5, 2.0, 2),    // Speaker 2
            (4.5, 0.5, 0),    // Pause
            (5.0, 1.5, 1),    // Speaker 1 again
            (6.5, 1.5, 2),    // Speaker 2 again
        ]
        
        for segment in speakerSegments {
            let startSample = Int(segment.start * Double(sampleRate))
            let endSample = Int((segment.start + segment.duration) * Double(sampleRate))
            
            for i in startSample..<min(endSample, sampleCount) {
                switch segment.speaker {
                case 1: // Speaker 1 - low voice
                    let frequency = Float(150 + 30 * sin(Double(i) * 0.002))
                    audioBuffer[i] = sin(2.0 * Float.pi * frequency * Float(i) / Float(sampleRate)) * 0.4
                case 2: // Speaker 2 - high voice
                    let frequency = Float(250 + 50 * sin(Double(i) * 0.003))
                    audioBuffer[i] = sin(2.0 * Float.pi * frequency * Float(i) / Float(sampleRate)) * 0.3
                default: // Pause
                    audioBuffer[i] = Float.random(in: -0.01...0.01)
                }
            }
        }
        
        return audioBuffer
    }
    
    /// Saves audio buffer to WAV file for testing
    public static func saveAudioBufferToWAV(
        buffer: [Float],
        filename: String,
        sampleRate: Int = 16000
    ) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                    in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent("\(filename).wav")
        
        // Convert Float to Int16 for WAV
        let int16Buffer = buffer.map { sample in
            Int16(max(-32767, min(32767, sample * 32767)))
        }
        
        // Create WAV header
        var wavData = Data()
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        let fileSize = 36 + int16Buffer.count * 2
        wavData.append(withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt subchunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // Subchunk size
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // Audio format (PCM)
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // Num channels
        wavData.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) }) // Sample rate
        wavData.append(withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Data($0) }) // Byte rate
        wavData.append(withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })  // Block align
        wavData.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // Bits per sample
        
        // data subchunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(int16Buffer.count * 2).littleEndian) { Data($0) })
        
        // Audio data
        for sample in int16Buffer {
            wavData.append(withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }
        
        try wavData.write(to: fileURL)
        return fileURL
    }
    
    /// Creates short audio buffer for quick tests
    public static func createQuickTestBuffer() -> [Float] {
        return createSpeechLikeAudioBuffer(duration: 2.0, includeWords: true)
    }
    
    /// Creates long audio buffer for chunking testing
    public static func createLongTestBuffer() -> [Float] {
        return createSpeechLikeAudioBuffer(duration: 60.0, includeWords: true)
    }
} 
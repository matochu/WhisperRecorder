import Foundation
import AVFoundation

// MARK: - Segment-wise Whisper Processing (inspired by whispy)
// This approach first diarizes the audio, then transcribes each speaker segment separately
// for potentially better quality than processing the entire audio at once

class WhisperSegmentProcessor {
    static let shared = WhisperSegmentProcessor()
    
    private init() {}
    
    /// Process audio using segment-wise approach:
    /// 1. Diarize audio to get speaker segments
    /// 2. Transcribe each segment separately 
    /// 3. Merge results with timeline preservation
    func processAudioWithSegments(
        audioURL: URL,
        whisperWrapper: WhisperWrapper,
        diarizationEngine: SpeakerDiarizationEngine,
        progressCallback: @escaping (Float) -> Void,
        completion: @escaping (Result<SegmentedTranscription, Error>) -> Void
    ) {
        logInfo(.whisper, "🔄 Starting segment-wise processing for: \(audioURL.lastPathComponent)")
        startTiming("segment_wise_processing")
        
        // Step 1: Perform speaker diarization first
        progressCallback(0.1)
        diarizationEngine.processSpeakerDiarization(audioURL: audioURL) { diarizationResult in
            switch diarizationResult {
            case .success(let timeline):
                logInfo(.whisper, "📊 Diarization completed: \(timeline.segments.count) segments")
                
                // Step 2: Process each segment with Whisper
                self.processSegments(
                    audioURL: audioURL,
                    timeline: timeline,
                    whisperWrapper: whisperWrapper,
                    progressCallback: { segmentProgress in
                        // Map segment progress to overall progress (10% - 90%)
                        progressCallback(0.1 + (segmentProgress * 0.8))
                    },
                    completion: { segmentResult in
                        switch segmentResult {
                        case .success(let segmentedTranscription):
                            logInfo(.whisper, "✅ Segment-wise processing completed")
                            _ = endTiming("segment_wise_processing")
                            progressCallback(1.0)
                            completion(.success(segmentedTranscription))
                            
                        case .failure(let error):
                            logError(.whisper, "❌ Segment processing failed: \(error)")
                            _ = endTiming("segment_wise_processing")
                            completion(.failure(error))
                        }
                    }
                )
                
            case .failure(let error):
                logError(.whisper, "❌ Diarization failed: \(error)")
                _ = endTiming("segment_wise_processing")
                completion(.failure(error))
            }
        }
    }
    
    private func processSegments(
        audioURL: URL,
        timeline: SpeakerTimeline,
        whisperWrapper: WhisperWrapper,
        progressCallback: @escaping (Float) -> Void,
        completion: @escaping (Result<SegmentedTranscription, Error>) -> Void
    ) {
        let segments = timeline.segments
        guard !segments.isEmpty else {
            completion(.success(SegmentedTranscription(segments: [], timeline: timeline)))
            return
        }
        
        var processedSegments: [ProcessedSegment] = []
        var currentIndex = 0
        
        func processNextSegment() {
            guard currentIndex < segments.count else {
                // All segments processed
                let result = SegmentedTranscription(segments: processedSegments, timeline: timeline)
                completion(.success(result))
                return
            }
            
            let segment = segments[currentIndex]
            let progress = Float(currentIndex) / Float(segments.count)
            progressCallback(progress)
            
            logInfo(.whisper, "🎙️ Processing segment \(currentIndex + 1)/\(segments.count) for \(segment.speakerID)")
            
            // Extract audio segment
            extractAudioSegment(
                from: audioURL,
                startTime: segment.startTime,
                duration: segment.duration
            ) { extractResult in
                switch extractResult {
                case .success(let segmentAudioURL):
                    // Transcribe this segment
                    whisperWrapper.transcribe(audioFile: segmentAudioURL) { transcribeResult in
                        switch transcribeResult {
                        case .success(let transcription):
                            // Detect language for this segment if enabled
                            let detectedLanguage = self.detectLanguageForSegment(transcription)
                            
                            let processedSegment = ProcessedSegment(
                                originalSegment: segment,
                                transcription: transcription,
                                detectedLanguage: detectedLanguage,
                                confidence: self.calculateConfidence(transcription)
                            )
                            
                            processedSegments.append(processedSegment)
                            logInfo(.whisper, "✅ Segment \(currentIndex + 1) completed: '\(transcription.prefix(50))'")
                            
                        case .failure(let error):
                            logWarning(.whisper, "⚠️ Segment \(currentIndex + 1) failed: \(error), using empty transcription")
                            
                            let processedSegment = ProcessedSegment(
                                originalSegment: segment,
                                transcription: "[Transcription failed]",
                                detectedLanguage: "unknown",
                                confidence: 0.0
                            )
                            processedSegments.append(processedSegment)
                        }
                        
                        // Clean up temporary audio file
                        try? FileManager.default.removeItem(at: segmentAudioURL)
                        
                        // Process next segment
                        currentIndex += 1
                        processNextSegment()
                    }
                    
                case .failure(let error):
                    logError(.whisper, "❌ Failed to extract audio segment: \(error)")
                    
                    // Add empty segment and continue
                    let processedSegment = ProcessedSegment(
                        originalSegment: segment,
                        transcription: "[Audio extraction failed]",
                        detectedLanguage: "unknown",
                        confidence: 0.0
                    )
                    processedSegments.append(processedSegment)
                    
                    currentIndex += 1
                    processNextSegment()
                }
            }
        }
        
        processNextSegment()
    }
    
    private func extractAudioSegment(
        from audioURL: URL,
        startTime: TimeInterval,
        duration: TimeInterval,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Create temporary file for segment
        let tempDir = FileManager.default.temporaryDirectory
        let segmentURL = tempDir.appendingPathComponent("segment_\(UUID().uuidString).wav")
        
        // Use AVAssetExportSession to extract segment
        let asset = AVAsset(url: audioURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(.failure(SegmentProcessingError.exportSessionCreationFailed))
            return
        }
        
        exportSession.outputURL = segmentURL
        exportSession.outputFileType = .wav
        
        // Set time range for the segment
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
        let durationCMTime = CMTime(seconds: duration, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCMTime, duration: durationCMTime)
        exportSession.timeRange = timeRange
        
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                completion(.success(segmentURL))
            case .failed:
                completion(.failure(exportSession.error ?? SegmentProcessingError.exportFailed))
            case .cancelled:
                completion(.failure(SegmentProcessingError.exportCancelled))
            default:
                completion(.failure(SegmentProcessingError.exportFailed))
            }
        }
    }
    
    private func detectLanguageForSegment(_ transcription: String) -> String {
        // Simple language detection based on character patterns
        // In real implementation, could use more sophisticated detection
        let hasLatin = transcription.range(of: "[a-zA-Z]", options: .regularExpression) != nil
        let hasCyrillic = transcription.range(of: "[а-яёА-ЯЁ]", options: .regularExpression) != nil
        
        if hasCyrillic {
            return "uk" // Ukrainian/Russian
        } else if hasLatin {
            return "en" // English
        } else {
            return "auto"
        }
    }
    
    private func calculateConfidence(_ transcription: String) -> Float {
        // Simple confidence calculation based on transcription length and content
        let hasWords = !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let wordCount = transcription.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        
        if !hasWords {
            return 0.0
        } else if wordCount > 5 {
            return 0.9
        } else {
            return Float(wordCount) * 0.15
        }
    }
}

// MARK: - Data Structures

struct SegmentedTranscription {
    let segments: [ProcessedSegment]
    let timeline: SpeakerTimeline
    
    var combinedText: String {
        return segments
            .sorted { $0.originalSegment.startTime < $1.originalSegment.startTime }
            .map { segment in
                "[\(segment.originalSegment.speakerID)] \(segment.transcription)"
            }
            .joined(separator: "\n")
    }
    
    var averageConfidence: Float {
        guard !segments.isEmpty else { return 0.0 }
        let totalConfidence = segments.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Float(segments.count)
    }
}

struct ProcessedSegment {
    let originalSegment: SpeakerSegment
    let transcription: String
    let detectedLanguage: String
    let confidence: Float
    
    var speakerID: String {
        return originalSegment.speakerID
    }
    
    var startTime: TimeInterval {
        return originalSegment.startTime
    }
    
    var duration: TimeInterval {
        return originalSegment.duration
    }
}

// MARK: - Errors

enum SegmentProcessingError: Error, LocalizedError {
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled
    case audioLoadingFailed
    
    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "Failed to create audio export session"
        case .exportFailed:
            return "Audio segment export failed"
        case .exportCancelled:
            return "Audio segment export was cancelled"
        case .audioLoadingFailed:
            return "Failed to load audio for processing"
        }
    }
} 
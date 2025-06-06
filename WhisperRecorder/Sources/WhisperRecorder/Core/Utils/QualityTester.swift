import Foundation
import AVFoundation

// MARK: - Quality Testing System (inspired by whispy)
// Tests different hyperparameters and configurations to find optimal settings

class QualityTester {
    static let shared = QualityTester()
    
    private init() {}
    
    /// Test different configurations and report quality metrics
    func runQualityTest(
        audioURL: URL,
        testConfigurations: [TestConfiguration] = TestConfiguration.defaultConfigurations,
        progressCallback: @escaping (Float, String) -> Void,
        completion: @escaping (QualityTestResult) -> Void
    ) {
        logInfo(.whisper, "🧪 Starting quality test with \(testConfigurations.count) configurations")
        startTiming("quality_test")
        
        var results: [ConfigurationResult] = []
        var currentIndex = 0
        
        func testNextConfiguration() {
            guard currentIndex < testConfigurations.count else {
                // All tests completed
                let testResult = QualityTestResult(results: results)
                logInfo(.whisper, "✅ Quality test completed")
                _ = endTiming("quality_test")
                completion(testResult)
                return
            }
            
            let config = testConfigurations[currentIndex]
            let progress = Float(currentIndex) / Float(testConfigurations.count)
            progressCallback(progress, "Testing \(config.name)")
            
            logInfo(.whisper, "🔬 Testing configuration: \(config.name)")
            
            testConfiguration(config, audioURL: audioURL) { result in
                results.append(result)
                currentIndex += 1
                testNextConfiguration()
            }
        }
        
        testNextConfiguration()
    }
    
    private func testConfiguration(
        _ config: TestConfiguration,
        audioURL: URL,
        completion: @escaping (ConfigurationResult) -> Void
    ) {
        let startTime = Date()
        
        // Apply configuration to whisper wrapper
        let whisperWrapper = WhisperWrapper.shared
        let originalBeamSize = whisperWrapper.beamSearchSize
        let originalTemperature = whisperWrapper.temperature
        let originalSegmentWise = whisperWrapper.segmentWiseProcessing
        
        // Set test configuration
        whisperWrapper.beamSearchSize = config.beamSize
        whisperWrapper.temperature = config.temperature
        whisperWrapper.segmentWiseProcessing = config.useSegmentWise
        
        // Perform transcription
        if config.useSegmentWise {
            testSegmentWiseTranscription(config: config, audioURL: audioURL, startTime: startTime) { result in
                // Restore original settings
                whisperWrapper.beamSearchSize = originalBeamSize
                whisperWrapper.temperature = originalTemperature
                whisperWrapper.segmentWiseProcessing = originalSegmentWise
                
                completion(result)
            }
        } else {
            testStandardTranscription(config: config, audioURL: audioURL, startTime: startTime) { result in
                // Restore original settings
                whisperWrapper.beamSearchSize = originalBeamSize
                whisperWrapper.temperature = originalTemperature
                whisperWrapper.segmentWiseProcessing = originalSegmentWise
                
                completion(result)
            }
        }
    }
    
    private func testStandardTranscription(
        config: TestConfiguration,
        audioURL: URL,
        startTime: Date,
        completion: @escaping (ConfigurationResult) -> Void
    ) {
        WhisperWrapper.shared.transcribe(audioFile: audioURL) { result in
            let processingTime = Date().timeIntervalSince(startTime)
            
            switch result {
            case .success(let transcription):
                let metrics = self.calculateMetrics(
                    transcription: transcription,
                    processingTime: processingTime,
                    segmentCount: 1
                )
                
                let configResult = ConfigurationResult(
                    configuration: config,
                    success: true,
                    transcription: transcription,
                    metrics: metrics,
                    error: nil
                )
                
                completion(configResult)
                
            case .failure(let error):
                let configResult = ConfigurationResult(
                    configuration: config,
                    success: false,
                    transcription: "",
                    metrics: QualityMetrics.empty,
                    error: error
                )
                
                completion(configResult)
            }
        }
    }
    
    private func testSegmentWiseTranscription(
        config: TestConfiguration,
        audioURL: URL,
        startTime: Date,
        completion: @escaping (ConfigurationResult) -> Void
    ) {
        WhisperSegmentProcessor.shared.processAudioWithSegments(
            audioURL: audioURL,
            whisperWrapper: WhisperWrapper.shared,
            diarizationEngine: SpeakerDiarizationEngine.shared,
            progressCallback: { _ in /* No need to track sub-progress in tests */ },
            completion: { result in
                let processingTime = Date().timeIntervalSince(startTime)
                
                switch result {
                case .success(let segmentedTranscription):
                    let metrics = self.calculateMetrics(
                        transcription: segmentedTranscription.combinedText,
                        processingTime: processingTime,
                        segmentCount: segmentedTranscription.segments.count
                    )
                    
                    let configResult = ConfigurationResult(
                        configuration: config,
                        success: true,
                        transcription: segmentedTranscription.combinedText,
                        metrics: metrics,
                        error: nil
                    )
                    
                    completion(configResult)
                    
                case .failure(let error):
                    let configResult = ConfigurationResult(
                        configuration: config,
                        success: false,
                        transcription: "",
                        metrics: QualityMetrics.empty,
                        error: error
                    )
                    
                    completion(configResult)
                }
            }
        )
    }
    
    private func calculateMetrics(
        transcription: String,
        processingTime: TimeInterval,
        segmentCount: Int
    ) -> QualityMetrics {
        let wordCount = transcription.components(separatedBy: .whitespaces)
            .filter { !$0.trimmingCharacters(in: .punctuationCharacters).isEmpty }.count
        
        let characterCount = transcription.count
        let hasText = !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        // Simple quality score based on various factors
        var qualityScore: Float = 0.0
        
        if hasText {
            qualityScore += 0.3 // Base score for having text
            
            if wordCount > 0 {
                qualityScore += min(Float(wordCount) * 0.01, 0.4) // More words = better
            }
            
            if characterCount > 0 {
                qualityScore += min(Float(characterCount) * 0.001, 0.2) // More characters = better
            }
            
            // Penalize very long processing times
            if processingTime < 30.0 {
                qualityScore += 0.1
            }
        }
        
        qualityScore = min(qualityScore, 1.0)
        
        return QualityMetrics(
            wordCount: wordCount,
            characterCount: characterCount,
            processingTime: processingTime,
            qualityScore: qualityScore,
            segmentCount: segmentCount,
            hasText: hasText
        )
    }
}

// MARK: - Test Configuration

struct TestConfiguration {
    let name: String
    let beamSize: Int
    let temperature: Float
    let useSegmentWise: Bool
    
    static let defaultConfigurations: [TestConfiguration] = [
        TestConfiguration(name: "Fast (Beam=1)", beamSize: 1, temperature: 0.0, useSegmentWise: false),
        TestConfiguration(name: "Balanced (Beam=3)", beamSize: 3, temperature: 0.0, useSegmentWise: false),
        TestConfiguration(name: "Quality (Beam=5)", beamSize: 5, temperature: 0.0, useSegmentWise: false),
        TestConfiguration(name: "High Quality (Beam=8)", beamSize: 8, temperature: 0.0, useSegmentWise: false),
        TestConfiguration(name: "Creative (Beam=5, Temp=0.2)", beamSize: 5, temperature: 0.2, useSegmentWise: false),
        TestConfiguration(name: "Segment-wise (Beam=5)", beamSize: 5, temperature: 0.0, useSegmentWise: true),
    ]
}

// MARK: - Results

struct QualityTestResult {
    let results: [ConfigurationResult]
    
    var bestConfiguration: ConfigurationResult? {
        return results
            .filter { $0.success }
            .max { $0.metrics.qualityScore < $1.metrics.qualityScore }
    }
    
    var fastestConfiguration: ConfigurationResult? {
        return results
            .filter { $0.success }
            .min { $0.metrics.processingTime < $1.metrics.processingTime }
    }
    
    var summary: String {
        let successCount = results.filter { $0.success }.count
        let totalCount = results.count
        
        var summary = "Quality Test Results:\n"
        summary += "✅ Successful: \(successCount)/\(totalCount)\n\n"
        
        if let best = bestConfiguration {
            summary += "🏆 Best Quality: \(best.configuration.name)\n"
            summary += "   Score: \(String(format: "%.2f", best.metrics.qualityScore))\n"
            summary += "   Words: \(best.metrics.wordCount)\n"
            summary += "   Time: \(String(format: "%.1f", best.metrics.processingTime))s\n\n"
        }
        
        if let fastest = fastestConfiguration {
            summary += "⚡ Fastest: \(fastest.configuration.name)\n"
            summary += "   Time: \(String(format: "%.1f", fastest.metrics.processingTime))s\n"
            summary += "   Score: \(String(format: "%.2f", fastest.metrics.qualityScore))\n\n"
        }
        
        summary += "📊 All Results:\n"
        for result in results.sorted(by: { $0.metrics.qualityScore > $1.metrics.qualityScore }) {
            let status = result.success ? "✅" : "❌"
            summary += "\(status) \(result.configuration.name): "
            if result.success {
                summary += "Score \(String(format: "%.2f", result.metrics.qualityScore)), "
                summary += "\(String(format: "%.1f", result.metrics.processingTime))s"
            } else {
                summary += "Failed"
            }
            summary += "\n"
        }
        
        return summary
    }
}

struct ConfigurationResult {
    let configuration: TestConfiguration
    let success: Bool
    let transcription: String
    let metrics: QualityMetrics
    let error: Error?
}

struct QualityMetrics {
    let wordCount: Int
    let characterCount: Int
    let processingTime: TimeInterval
    let qualityScore: Float
    let segmentCount: Int
    let hasText: Bool
    
    static let empty = QualityMetrics(
        wordCount: 0,
        characterCount: 0,
        processingTime: 0,
        qualityScore: 0,
        segmentCount: 0,
        hasText: false
    )
} 
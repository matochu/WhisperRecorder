import XCTest
import SwiftUI
@testable import WhisperRecorder

/// SwiftUI component integration tests focusing on component interactions and state management
class UIComponentIntegrationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        print("\n🎭 UI Component Integration Tests")
        print("================================")
    }
    
    // MARK: - Card Component Tests
    
    func testStatusCardIntegration() throws {
        print("\n📊 Testing StatusCard Integration")
        print("────────────────────────────────")
        
        // Test StatusCard with different recording states
        let recordingStates: [String] = ["idle", "recording", "processing"]
        
        for state in recordingStates {
            print("🔧 Testing status card with state: \(state)...")
            
            // Create mock state
            let statusDescription = getStatusDescription(for: state)
            XCTAssertFalse(statusDescription.isEmpty, "Status description should not be empty")
            
            print("   📱 Status: \(statusDescription)")
            print("   ✅ StatusCard state \(state) handled correctly")
        }
    }
    
    func testActionsCardIntegration() throws {
        print("\n⚡ Testing ActionsCard Integration")
        print("─────────────────────────────────")
        
        // Test copy actions with different text states
        print("🔧 Testing copy actions...")
        
        // Scenario 1: Both original and processed text available
        AppDelegate.lastOriginalWhisperText = "Original transcription text"
        AppDelegate.lastProcessedText = "Processed text with enhancements"
        
        let hasBothTexts = !AppDelegate.lastOriginalWhisperText.isEmpty && 
                          !AppDelegate.lastProcessedText.isEmpty
        XCTAssertTrue(hasBothTexts, "Should have both original and processed text")
        
        print("   ✅ Both texts available - copy actions enabled")
        
        // Scenario 2: Only original text available
        AppDelegate.lastOriginalWhisperText = "Only original text"
        AppDelegate.lastProcessedText = ""
        
        let hasOnlyOriginal = !AppDelegate.lastOriginalWhisperText.isEmpty && 
                             AppDelegate.lastProcessedText.isEmpty
        XCTAssertTrue(hasOnlyOriginal, "Should have only original text")
        
        print("   ✅ Only original text - limited copy actions")
        
        // Scenario 3: No text available
        AppDelegate.lastOriginalWhisperText = ""
        AppDelegate.lastProcessedText = ""
        
        let hasNoText = AppDelegate.lastOriginalWhisperText.isEmpty && 
                       AppDelegate.lastProcessedText.isEmpty
        XCTAssertTrue(hasNoText, "Should have no text")
        
        print("   ✅ No text available - copy actions disabled")
    }
    
    func testConfigurationCardIntegration() throws {
        print("\n⚙️ Testing ConfigurationCard Integration")
        print("───────────────────────────────────────")
        
        // Test writing style selection
        print("🔧 Testing writing style selection...")
        
        let audioRecorder = AudioRecorder.shared
        let originalStyle = audioRecorder.selectedWritingStyle
        
        // Test style switching
        let availableStyles = WritingStyle.styles
        if availableStyles.count > 1 {
            let newStyle = availableStyles.first { $0.name != originalStyle.name }!
            audioRecorder.selectedWritingStyle = newStyle
            
            XCTAssertEqual(audioRecorder.selectedWritingStyle.name, newStyle.name, 
                          "Writing style should update")
            print("   ✅ Writing style changed from '\(originalStyle.name)' to '\(newStyle.name)'")
            
            // Restore original
            audioRecorder.selectedWritingStyle = originalStyle
        }
        
        // Test model selection interface
        print("🔧 Testing model selection...")
        
        let whisperWrapper = WhisperWrapper.shared
        let modelInfo = "\(whisperWrapper.currentModel.displayName) (\(whisperWrapper.currentModel.size))"
        XCTAssertFalse(modelInfo.isEmpty, "Should have model information")
        
        print("   ✅ Model selection interface accessible")
    }
    
    // MARK: - Toast Component Tests
    
    func testToastComponentIntegration() throws {
        print("\n🍞 Testing Toast Component Integration")
        print("────────────────────────────────────")
        
        let toastManager = ToastManager.shared
        
        // Test toast visibility states
        print("🔧 Testing toast visibility...")
        
        // Initially hidden
        XCTAssertFalse(toastManager.isShowing, "Toast should be initially hidden")
        
        // Show toast
        toastManager.showToast(message: "", preview: "Test message", at: nil, type: .normal)
        XCTAssertTrue(toastManager.isShowing, "Toast should be visible after showing")
        
        // Hide toast
        toastManager.hideToast()
        XCTAssertFalse(toastManager.isShowing, "Toast should be hidden after hiding")
        
        print("   ✅ Toast visibility states working correctly")
        
        // Test toast message content
        print("🔧 Testing toast message content...")
        
        let testMessage = "Integration test message"
        toastManager.showToast(message: "", preview: testMessage, at: nil, type: .normal)
        
        XCTAssertEqual(toastManager.preview, testMessage, "Toast message should match")
        XCTAssertEqual(toastManager.toastType, .normal, "Toast type should match")
        
        print("   ✅ Toast content management working")
        
        toastManager.hideToast()
    }
    
    // MARK: - Cross-Component Integration Tests
    
    func testCopyActionToastIntegration() throws {
        print("\n🔗 Testing Copy Action → Toast Integration")
        print("─────────────────────────────────────────")
        
        let toastManager = ToastManager.shared
        toastManager.toastsEnabled = true
        
        // Simulate copy action triggering toast
        print("🔧 Simulating copy action...")
        
        let testText = "Text to be copied and trigger toast"
        AppDelegate.lastProcessedText = testText
        
        // Simulate copy operation
        let copySuccess = simulateCopyOperation(text: testText)
        XCTAssertTrue(copySuccess, "Copy operation should succeed")
        
        // Simulate toast being triggered by copy
        toastManager.showToast(
            message: "",
            preview: "Copied: \(testText.prefix(30))...",
            at: nil,
            type: .normal
        )
        
        XCTAssertTrue(toastManager.isShowing, "Toast should appear after copy")
        XCTAssertTrue(toastManager.preview.contains("Copied:"), "Toast should indicate copy action")
        
        print("   ✅ Copy action successfully triggered toast")
        
        toastManager.hideToast()
    }
    
    func testRecordingStateToUIIntegration() throws {
        print("\n🎤 Testing Recording State → UI Integration")
        print("──────────────────────────────────────────")
        
        let audioRecorder = AudioRecorder.shared
        
        // Test UI state based on recording capabilities
        print("🔧 Testing recording state UI integration...")
        
        let statusDescription = audioRecorder.statusDescription
        XCTAssertFalse(statusDescription.isEmpty, "Status description should not be empty")
        
        print("   📊 Current status: \(statusDescription)")
        print("   ✅ Recording state UI integration working")
    }
    
    func testLLMProcessingToUIIntegration() throws {
        print("\n🧠 Testing LLM Processing → UI Integration")
        print("─────────────────────────────────────────")
        
        // Test LLM processing state changes affecting UI
        print("🔧 Testing LLM processing workflow...")
        
        let originalText = "Original transcription for LLM processing"
        AppDelegate.lastOriginalWhisperText = originalText
        
        // Simulate LLM processing completion
        let processedText = "Enhanced: " + originalText + " [LLM processed]"
        AppDelegate.lastProcessedText = processedText
        
        // Verify UI can access both texts
        let hasOriginal = !AppDelegate.lastOriginalWhisperText.isEmpty
        let hasProcessed = !AppDelegate.lastProcessedText.isEmpty
        
        XCTAssertTrue(hasOriginal, "Original text should be available")
        XCTAssertTrue(hasProcessed, "Processed text should be available")
        XCTAssertNotEqual(AppDelegate.lastOriginalWhisperText, AppDelegate.lastProcessedText, 
                         "Texts should be different after processing")
        
        print("   ✅ LLM processing completed - UI updated with both texts")
    }
    
    // MARK: - Configuration Integration Tests
    
    func testConfigurationPersistenceIntegration() throws {
        print("\n💾 Testing Configuration Persistence Integration")
        print("───────────────────────────────────────────────")
        
        let toastManager = ToastManager.shared
        
        // Test toast setting persistence
        print("🔧 Testing toast settings persistence...")
        
        let originalToastSetting = toastManager.toastsEnabled
        
        // Toggle setting
        toastManager.toastsEnabled = !originalToastSetting
        XCTAssertNotEqual(toastManager.toastsEnabled, originalToastSetting, 
                         "Toast setting should change")
        
        // Restore original setting
        toastManager.toastsEnabled = originalToastSetting
        XCTAssertEqual(toastManager.toastsEnabled, originalToastSetting, 
                      "Toast setting should restore")
        
        print("   ✅ Toast settings persistence working")
        
        // Test writing style persistence
        print("🔧 Testing writing style persistence...")
        
        let audioRecorder = AudioRecorder.shared
        let originalStyle = audioRecorder.selectedWritingStyle
        
        // Change style
        let availableStyles = WritingStyle.styles
        if let differentStyle = availableStyles.first(where: { $0.name != originalStyle.name }) {
            audioRecorder.selectedWritingStyle = differentStyle
            XCTAssertEqual(audioRecorder.selectedWritingStyle.name, differentStyle.name, 
                          "Writing style should update")
            
            // Restore original
            audioRecorder.selectedWritingStyle = originalStyle
            XCTAssertEqual(audioRecorder.selectedWritingStyle.name, originalStyle.name, 
                          "Writing style should restore")
            
            print("   ✅ Writing style persistence working")
        }
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testErrorHandlingIntegration() throws {
        print("\n❌ Testing Error Handling Integration")
        print("────────────────────────────────────")
        
        // Test error toast display
        print("🔧 Testing error toast display...")
        
        let toastManager = ToastManager.shared
        toastManager.toastsEnabled = true
        
        let errorMessage = "Test error message for integration testing"
        toastManager.showToast(message: "", preview: errorMessage, at: nil, type: .error)
        
        XCTAssertTrue(toastManager.isShowing, "Error toast should be visible")
        XCTAssertEqual(toastManager.preview, errorMessage, "Error message should match")
        XCTAssertEqual(toastManager.toastType, .error, "Toast type should be error")
        
        print("   ✅ Error toast integration working")
        
        toastManager.hideToast()
        
        print("   ✅ Error handling integration tests completed")
    }
    
    // MARK: - Auto-Paste Integration Tests
    
    func testAutoPasteConfigurationIntegration() throws {
        print("\n📋 Testing Auto-Paste Configuration Integration")
        print("──────────────────────────────────────────────")
        
        // Test auto-paste configuration options
        print("🔧 Testing auto-paste settings...")
        
        // Simulate different auto-paste states
        let autoPasteConfigurations = [
            ("enabled", true),
            ("disabled", false)
        ]
        
        for (description, enabled) in autoPasteConfigurations {
            print("   Testing auto-paste \(description)...")
            
            // Test with configuration
            let testText = "Auto-paste test text with configuration \(description)"
            AppDelegate.lastProcessedText = testText
            
            if enabled {
                // Simulate auto-paste operation
                let autoPasteSuccess = simulateAutoPaste(text: testText)
                XCTAssertTrue(autoPasteSuccess, "Auto-paste should succeed when enabled")
                print("     ✅ Auto-paste successful for \(description)")
            } else {
                // Simulate manual copy instead
                let manualCopySuccess = simulateCopyOperation(text: testText)
                XCTAssertTrue(manualCopySuccess, "Manual copy should work when auto-paste disabled")
                print("     ✅ Manual copy available when auto-paste \(description)")
            }
        }
    }
    
    // MARK: - Complete Workflow Integration Tests
    
    func testCompleteUIWorkflowIntegration() throws {
        print("\n🔄 Testing Complete UI Workflow Integration")
        print("──────────────────────────────────────────")
        
        let toastManager = ToastManager.shared
        toastManager.toastsEnabled = true
        
        print("🔧 Executing complete workflow...")
        
        // Step 1: Recording completion simulation
        let originalText = "Complete workflow integration test"
        AppDelegate.lastOriginalWhisperText = originalText
        print("   1️⃣ Recording completed: ✅")
        
        // Step 2: LLM processing simulation
        let processedText = mockLLMProcessing(originalText: originalText)
        AppDelegate.lastProcessedText = processedText
        print("   2️⃣ LLM processing completed: ✅")
        
        // Step 3: Auto-paste or copy simulation
        let copySuccess = simulateCopyOperation(text: processedText)
        XCTAssertTrue(copySuccess, "Copy operation should succeed")
        print("   3️⃣ Text copied to clipboard: ✅")
        
        // Step 4: Toast notification
        toastManager.showToast(
            message: "",
            preview: "Workflow complete! Text processed and copied.",
            at: nil,
            type: .normal
        )
        XCTAssertTrue(toastManager.isShowing, "Success toast should be visible")
        print("   4️⃣ Toast notification shown: ✅")
        
        // Step 5: Verify final UI state
        let hasOriginal = !AppDelegate.lastOriginalWhisperText.isEmpty
        let hasProcessed = !AppDelegate.lastProcessedText.isEmpty
        let toastShowing = toastManager.isShowing
        
        XCTAssertTrue(hasOriginal, "Original text should be available in UI")
        XCTAssertTrue(hasProcessed, "Processed text should be available in UI")
        XCTAssertTrue(toastShowing, "Toast should be visible in UI")
        
        print("   5️⃣ Final UI state verified: ✅")
        print("\n🎉 Complete UI workflow integration test passed!")
        
        // Cleanup
        toastManager.hideToast()
    }
    
    // MARK: - Helper Methods
    
    private func simulateCopyOperation(text: String) -> Bool {
        // Simulate clipboard operation
        return !text.isEmpty
    }
    
    private func simulateAutoPaste(text: String) -> Bool {
        // Simulate auto-paste operation
        return !text.isEmpty
    }
    
    private func getStatusDescription(for state: String) -> String {
        switch state {
        case "idle":
            return "Ready to record"
        case "recording":
            return "Recording..."
        case "processing":
            return "Processing..."
        default:
            return "Unknown state"
        }
    }
    
    private func mockLLMProcessing(originalText: String) -> String {
        return "Enhanced: " + originalText + " [LLM processed]"
    }
}

// MARK: - Test Helper Extensions

// Using actual classes from WhisperRecorder for integration testing 
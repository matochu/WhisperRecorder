#!/bin/bash

echo "🧪 WhisperRecorder E2E Testing Suite"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if in correct directory
if [ ! -f "Package.swift" ]; then
    echo -e "${RED}❌ Error: Must run from WhisperRecorder directory${NC}"
    exit 1
fi

# Function to ensure libwhisper libraries are available for tests
ensure_test_libraries() {
    echo -e "${BLUE}🔧 Ensuring test libraries are available...${NC}"
    
    BUILD_DIR=".build/arm64-apple-macosx/debug"
    LIBS_DIR="libs"
    
    # Check if build directory exists
    if [ ! -d "$BUILD_DIR" ]; then
        echo -e "${YELLOW}⚠️ Build directory not found. Running swift build first...${NC}"
        swift build
    fi
    
    # Copy required libraries to build directory if they exist
    if [ -d "$LIBS_DIR" ]; then
        echo -e "${BLUE}📚 Copying whisper libraries to test build directory...${NC}"
        
        # Copy whisper libraries
        for lib in "$LIBS_DIR"/libwhisper*.dylib; do
            if [ -f "$lib" ]; then
                cp "$lib" "$BUILD_DIR/" 2>/dev/null && echo "  ✓ Copied $(basename "$lib")"
            fi
        done
        
        # Copy ggml libraries
        for lib in "$LIBS_DIR"/libggml*.dylib; do
            if [ -f "$lib" ]; then
                cp "$lib" "$BUILD_DIR/" 2>/dev/null && echo "  ✓ Copied $(basename "$lib")"
            fi
        done
        
        echo -e "${GREEN}✅ Libraries copied successfully${NC}"
    else
        echo -e "${YELLOW}⚠️ Libraries directory not found. Tests may fail without proper library setup.${NC}"
    fi
}

# Function to download test model if needed for real audio tests
download_test_model() {
    echo -e "${YELLOW}🤖 Preparing test model...${NC}"
    
    # Go to parent directory where TestModels is located
    if [ -f "../TestModels/download_test_model.sh" ]; then
        cd ..
        ./TestModels/download_test_model.sh
        cd WhisperRecorder
        echo -e "${GREEN}✅ Test model ready${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️ Test model download script not found${NC}"
        return 1
    fi
}

# Function to clean up test artifacts
cleanup_test_artifacts() {
    echo -e "${BLUE}🧹 Cleaning up test artifacts...${NC}"
    
    BUILD_DIR=".build/arm64-apple-macosx/debug"
    
    # Remove copied libraries from build directory
    if [ -d "$BUILD_DIR" ]; then
        rm -f "$BUILD_DIR"/libwhisper*.dylib 2>/dev/null
        rm -f "$BUILD_DIR"/libggml*.dylib 2>/dev/null
    fi
    
    # Clean up test model (save space)
    if [ -f "../TestModels/ggml-tiny.en.bin" ]; then
        echo -e "${BLUE}🗑️ Removing test model to save space...${NC}"
        rm -f "../TestModels/ggml-tiny.en.bin"
        rm -f "../TestModels/MODEL_INFO.txt"
        echo -e "${GREEN}✅ Test model cleaned up (81MB saved)${NC}"
    fi
    
    echo -e "${GREEN}✅ Test artifacts cleaned up${NC}"
}

# Function to run tests based on choice
run_tests() {
    local choice=$1
    
    # Ensure libraries are available before running any tests
    ensure_test_libraries
    
    case $choice in
        quick)
            echo -e "${YELLOW}🏃‍♂️ Running Quick E2E Tests (~21s)${NC}"
            echo -e "${BLUE}ℹ️ Simulated data, no Whisper model required${NC}"
            swift test --filter WhisperRecorderE2ETests
            ;;
        pre-commit)
            echo -e "${YELLOW}⚡ Running Pre-commit Tests (~2s)${NC}"
            echo -e "${BLUE}ℹ️ Fast validation for commits - UI components only${NC}"
            swift test --filter UIIntegrationTests --quiet
            ;;
        ui)
            echo -e "${YELLOW}🎨 Running UI Integration Tests (~1s)${NC}"
            echo -e "${BLUE}ℹ️ Component interaction validation${NC}"
            swift test --filter UIIntegrationTests
            ;;
        ui-e2e)
            echo -e "${YELLOW}🎭 Running UI Component E2E Tests (~0.3s)${NC}"
            echo -e "${BLUE}ℹ️ End-to-end UI component behavior${NC}"
            swift test --filter UIComponentE2ETests
            ;;
        ui-full)
            echo -e "${YELLOW}🎪 Running Complete UI Test Suite (~1.5s)${NC}"
            echo -e "${BLUE}ℹ️ All UI tests: Integration + E2E components${NC}"
            swift test --filter UIIntegrationTests && swift test --filter UIComponentE2ETests
            ;;
        performance)
            echo -e "${YELLOW}⚡ Running Performance Benchmarks (~5s)${NC}"
            echo -e "${BLUE}ℹ️ Memory usage and execution time measurement${NC}"
            swift test --filter WhisperRecorderE2ETests.WhisperRecorderE2ETests/testTranscriptionPerformance
            ;;
        real)
            echo -e "${YELLOW}🎯 Running Real Audio Tests${NC}"
            echo -e "${BLUE}ℹ️ Auto-downloading lightweight Whisper model for testing...${NC}"
            
            # Download test model
            if download_test_model; then
                echo -e "${GREEN}🚀 Starting real audio tests with test model...${NC}"
                swift test --filter WhisperRecorderRealAudioTests
            else
                echo -e "${RED}❌ Failed to download test model${NC}"
                echo -e "${YELLOW}💡 Tests will run with simulation fallback${NC}"
                swift test --filter WhisperRecorderRealAudioTests
            fi
            ;;
        all)
            echo -e "${YELLOW}🚀 Running Complete Validation Suite${NC}"
            echo -e "${BLUE}ℹ️ All available tests: E2E, UI, Performance, Real Audio${NC}"
            
            # Download test model for real audio tests
            download_test_model
            
            echo -e "${GREEN}📋 Starting complete test suite...${NC}"
            swift test --filter WhisperRecorderE2ETests
            swift test --filter UIIntegrationTests && swift test --filter UIComponentE2ETests
            swift test --filter WhisperRecorderRealAudioTests
            ;;
        *)
            echo -e "${RED}❌ Invalid choice: '$choice'${NC}"
            echo ""
            echo -e "${BLUE}📋 Valid options:${NC}"
            echo -e "${GREEN}Development:${NC} pre-commit, quick, ui, ui-e2e"
            echo -e "${GREEN}Validation:${NC} ui-full, performance, real"
            echo -e "${GREEN}Complete:${NC} all"
            echo ""
            echo -e "${YELLOW}💡 Try: ./whisper test quick${NC}"
            exit 1
            ;;
    esac
}

# Check if parameter provided
if [ $# -eq 0 ]; then
    # Interactive mode
    echo -e "${BLUE}📋 WhisperRecorder Test Suites${NC}"
    echo ""
    echo -e "${GREEN}🏃‍♂️ Development Tests (Fast):${NC}"
    echo "  1. pre-commit    Pre-commit tests (~2s) - Fast validation for commits"
    echo "  2. quick         Quick E2E tests (~21s) - Simulated data, no model required"
    echo "  3. ui            UI Integration tests (~1s) - Component interaction validation"
    echo "  4. ui-e2e        UI Component E2E tests (~0.3s) - End-to-end UI behavior"
    echo ""
    echo -e "${GREEN}🎯 Validation Tests:${NC}"
    echo "  5. ui-full       Complete UI suite (~1.5s) - All UI tests combined"
    echo "  6. real          Real audio tests - Requires downloaded Whisper model"
    echo "  7. performance   Performance benchmarks (~5s) - Memory and speed tests"
    echo ""
    echo -e "${GREEN}🚀 Complete Testing:${NC}"
    echo "  8. all           All available tests - Complete validation suite"
    echo ""
    echo -e "${YELLOW}💡 Recommendation: Start with 'quick' for development${NC}"
    echo ""
    
    read -p "Enter test choice: " choice
    
    # Convert number to test name if needed in interactive mode
    case "$choice" in
        1)
            choice="pre-commit"
            ;;
        2)
            choice="quick"
            ;;
        3)
            choice="ui"
            ;;
        4)
            choice="ui-e2e"
            ;;
        5)
            choice="ui-full"
            ;;
        6)
            choice="real"
            ;;
        7)
            choice="performance"
            ;;
        8)
            choice="all"
            ;;
    esac
else
    # Command line mode
    choice=$1
    echo -e "${BLUE}📋 Running test suite: $choice${NC}"
fi

run_tests $choice
test_result=$?

# Clean up test artifacts
cleanup_test_artifacts

echo ""
if [ $test_result -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo -e "${BLUE}📊 Test Summary:${NC}"
    echo "  • E2E tests validate full system integration"
    echo "  • Audio simulation tests work without real models"
    echo "  • Real audio tests require actual Whisper models"
    echo "  • Performance tests measure speed and memory"
else
    echo -e "${RED}❌ Some tests failed${NC}"
    echo -e "${YELLOW}💡 Tips for troubleshooting:${NC}"
    echo "  • Check if Whisper model is downloaded for real audio tests"
    echo "  • Verify all dependencies are properly linked"
    echo "  • Run ./whisper build to ensure clean build state"
fi

echo ""
echo -e "${BLUE}🔧 Development Commands:${NC}"
echo "  swift test --list-tests               # List all available tests"
echo "  swift test --filter testname          # Run specific test"
echo "  swift test --parallel                 # Run tests in parallel"
echo "  swift test --enable-code-coverage     # Generate coverage report"
echo ""
echo -e "${BLUE}🚀 Quick Commands:${NC}"
echo "  ./whisper test             # Interactive menu (this interface)"
echo "  ./whisper test quick       # Development testing (~21s)"
echo "  ./whisper test ui-full     # Complete UI validation (~1.5s)"
echo "  ./whisper test all         # Full test suite validation"
echo ""
echo -e "${BLUE}📚 Test Categories:${NC}"
echo -e "${GREEN}Development${NC}: pre-commit, quick, ui, ui-e2e ${YELLOW}Fast feedback for coding${NC}"
echo -e "${GREEN}Validation${NC}: ui-full, performance, real ${YELLOW}Quality assurance${NC}"
echo -e "${GREEN}Complete${NC}: all                        ${YELLOW}Full validation suite${NC}"

exit $test_result 
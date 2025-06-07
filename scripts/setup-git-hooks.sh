#!/bin/bash

# WhisperRecorder Git Hooks Setup Script
# Installs pre-commit and other git hooks for development workflow

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 WhisperRecorder Git Hooks Setup${NC}"
echo "=================================="

# Check if we're in the right directory
if [ ! -f "whisper" ] || [ ! -d ".git" ]; then
    echo -e "${RED}❌ Error: Must be run from project root directory with .git${NC}"
    echo "Expected files: whisper script and .git directory"
    exit 1
fi

# Create .git/hooks directory if it doesn't exist
if [ ! -d ".git/hooks" ]; then
    mkdir -p .git/hooks
    echo -e "${BLUE}📁 Created .git/hooks directory${NC}"
fi

# Install pre-commit hook
echo -e "${YELLOW}📋 Installing pre-commit hook...${NC}"

if [ -f ".githooks/pre-commit" ]; then
    cp .githooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo -e "${GREEN}✅ Pre-commit hook installed${NC}"
    echo "  • Runs quick tests before each commit"
    echo "  • Automatically triggered on 'git commit'"
    echo "  • Can be bypassed with 'git commit --no-verify'"
else
    echo -e "${RED}❌ Error: .githooks/pre-commit not found${NC}"
    exit 1
fi

# Test the pre-commit hook
echo ""
echo -e "${BLUE}🧪 Testing pre-commit hook installation...${NC}"

# Create a temporary test to see if hook works
if [ -f ".git/hooks/pre-commit" ] && [ -x ".git/hooks/pre-commit" ]; then
    echo -e "${GREEN}✅ Pre-commit hook is executable${NC}"
    
    # Show what the hook will do
    echo ""
    echo -e "${BLUE}📋 Hook behavior:${NC}"
    echo "  • Detects Swift file changes in WhisperRecorder/"
    echo "  • Runs fast pre-commit tests (./test-e2e.sh pre-commit)"
    echo "  • Prevents commit if tests fail"
    echo "  • Times out after 60 seconds"
    echo "  • Skips if no WhisperRecorder changes detected"
    
else
    echo -e "${RED}❌ Error: Pre-commit hook installation failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 Git hooks setup completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Next steps:${NC}"
echo "  1. Make changes to WhisperRecorder Swift files"
echo "  2. Run 'git add .' to stage changes"
echo "  3. Run 'git commit -m \"your message\"'"
echo "  4. Hook will automatically run quick tests"
echo ""
echo -e "${BLUE}🔧 Manual testing commands:${NC}"
echo "  cd WhisperRecorder"
echo "  ./test-e2e.sh pre-commit # Run the same tests as hook (~2s)"
echo "  ./test-e2e.sh quick      # Run full E2E tests (~21s)"
echo "  ./test-e2e.sh ui         # Run UI tests (~1s)"
echo "  ./test-e2e.sh all        # Run all available tests"
echo ""
echo -e "${YELLOW}💡 To bypass hook (emergency only):${NC}"
echo "  git commit --no-verify -m \"urgent fix\"" 
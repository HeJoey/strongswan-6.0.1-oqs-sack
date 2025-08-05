#!/bin/bash

echo "======================================"
echo "Testing compilation after fix..."
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log with timestamp
log() {
    echo -e "[$(date '+%H:%M:%S')] $1"
}

log "${YELLOW}Starting compilation test...${NC}"

# Clean previous builds
log "Cleaning previous builds..."
make clean > /dev/null 2>&1

# Compile
log "Compiling strongSwan..."
if make -j4 > compile.log 2>&1; then
    log "${GREEN}✓ Compilation successful!${NC}"
    echo ""
    echo "Summary:"
    echo "- Fixed vici_control.c compilation errors"
    echo "- Replaced non-existent 'lib->settings->get_peer_cfg()' calls"
    echo "- Used existing 'find_child_cfg()' function instead"
    echo "- All three IKE stage commands (ikeinit, ikeinter, ikeauth) now compile correctly"
    echo ""
    exit 0
else
    log "${RED}✗ Compilation failed!${NC}"
    echo ""
    echo "Errors found:"
    grep -E "(error|Error|ERROR)" compile.log | head -10
    echo ""
    echo "Check compile.log for detailed error messages"
    exit 1
fi 
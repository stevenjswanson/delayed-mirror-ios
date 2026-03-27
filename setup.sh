#!/bin/bash
# setup.sh — Generate and open the DelayedMirror Xcode project
# Run from the DelayedMirror folder:  bash setup.sh
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}──────────────────────────────────────────${NC}"
echo -e "${CYAN}  Delayed Mirror — Xcode Project Setup    ${NC}"
echo -e "${CYAN}──────────────────────────────────────────${NC}"

# ── 1. Ensure we're in the right directory ────────────────────────────────────
if [ ! -f "project.yml" ]; then
  echo -e "${RED}Error: Run this script from the DelayedMirror folder (where project.yml lives).${NC}"
  exit 1
fi

# ── 2. Install Homebrew if missing ────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# ── 3. Install XcodeGen if missing ────────────────────────────────────────────
if ! command -v xcodegen &>/dev/null; then
  echo -e "${CYAN}Installing XcodeGen via Homebrew...${NC}"
  brew install xcodegen
else
  echo -e "${GREEN}✓ XcodeGen already installed ($(xcodegen --version 2>/dev/null | head -1))${NC}"
fi

# ── 4. Generate the Xcode project ─────────────────────────────────────────────
echo -e "${CYAN}Generating DelayedMirror.xcodeproj...${NC}"
xcodegen generate

echo -e "${GREEN}✓ Project generated successfully!${NC}"

# ── 5. Open in Xcode ──────────────────────────────────────────────────────────
echo -e "${CYAN}Opening in Xcode...${NC}"
open DelayedMirror.xcodeproj

echo ""
echo -e "${GREEN}──────────────────────────────────────────────${NC}"
echo -e "${GREEN}  Done! Next steps:                           ${NC}"
echo -e "${GREEN}                                              ${NC}"
echo -e "${GREEN}  1. In Xcode: select your Team under         ${NC}"
echo -e "${GREEN}     Signing & Capabilities                   ${NC}"
echo -e "${GREEN}  2. Connect a real iPhone or iPad            ${NC}"
echo -e "${GREEN}     (camera won't work in Simulator)         ${NC}"
echo -e "${GREEN}  3. Press ⌘R to build and run               ${NC}"
echo -e "${GREEN}──────────────────────────────────────────────${NC}"

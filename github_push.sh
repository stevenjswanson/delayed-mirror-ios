#!/bin/bash
# github_push.sh
# Run from the DelayedMirror folder to push the project to a new GitHub repo.
# Usage:  bash github_push.sh
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}──────────────────────────────────────────${NC}"
echo -e "${CYAN}  Delayed Mirror — GitHub Push             ${NC}"
echo -e "${CYAN}──────────────────────────────────────────${NC}"

# ── Must run from the project root ────────────────────────────────────────────
if [ ! -f "project.yml" ]; then
  echo -e "${RED}Error: run this from the DelayedMirror folder.${NC}"
  exit 1
fi

# ── Install Homebrew if missing ───────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo -e "${CYAN}Installing Homebrew...${NC}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# ── Install gh CLI if missing ─────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo -e "${CYAN}Installing GitHub CLI (gh)...${NC}"
  brew install gh
fi

# ── Authenticate with GitHub if needed ───────────────────────────────────────
if ! gh auth status &>/dev/null; then
  echo -e "${YELLOW}You need to log in to GitHub. A browser window will open.${NC}"
  gh auth login
fi

# ── Git setup ─────────────────────────────────────────────────────────────────
if [ ! -d ".git" ]; then
  echo -e "${CYAN}Initialising git repository...${NC}"
  git init
  git branch -m main
fi

# Ensure user identity is set
if ! git config user.email &>/dev/null; then
  GH_EMAIL=$(gh api user --jq '.email // empty' 2>/dev/null || echo "")
  GH_NAME=$(gh api user --jq '.name // .login' 2>/dev/null || echo "Steven")
  git config user.email "${GH_EMAIL:-sjswanson@ucsd.edu}"
  git config user.name  "${GH_NAME:-Steven}"
fi

# Stage and commit everything (skip xcuserstate)
git add -A
git status --short

git commit -m "$(cat <<'EOF'
Initial commit: DelayedMirror iOS app

Live camera feed with configurable 1–30 s delay.
Supports pinch-to-zoom, zoom slider, and buffering indicator.
Built with AVFoundation + SwiftUI. No video is saved to disk.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)" 2>/dev/null || echo -e "${YELLOW}Nothing new to commit — repo is up to date.${NC}"

# ── Create GitHub repo and push ───────────────────────────────────────────────
echo -e "${CYAN}Creating GitHub repository...${NC}"

gh repo create delayed-mirror-ios \
  --public \
  --description "iOS app: live camera feed with adjustable delay (1–30 s), zoom, SwiftUI" \
  --source=. \
  --remote=origin \
  --push

REPO_URL=$(gh repo view --json url -q '.url' 2>/dev/null || echo "(see above)")

echo ""
echo -e "${GREEN}──────────────────────────────────────────────────────────${NC}"
echo -e "${GREEN}  Done! Your repo is live at:                             ${NC}"
echo -e "${GREEN}  ${REPO_URL}                                             ${NC}"
echo -e "${GREEN}──────────────────────────────────────────────────────────${NC}"

# Open repo in browser
gh repo view --web 2>/dev/null || true

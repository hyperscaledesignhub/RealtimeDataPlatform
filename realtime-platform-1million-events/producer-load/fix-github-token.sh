#!/bin/bash

# ================================================================================
# Fix GitHub Token - Create Token with Correct Scopes
# ================================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}Token Permission Error - Let's Fix It!${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo "The token you created doesn't have the right permissions."
echo ""

echo -e "${YELLOW}Follow these steps CAREFULLY:${NC}"
echo ""
echo "1. Open this URL in your browser:"
echo -e "   ${BLUE}https://github.com/settings/tokens/new${NC}"
echo ""
echo "2. Fill in:"
echo "   - Note: 'Docker GHCR Access'"
echo "   - Expiration: '90 days' (or No expiration)"
echo ""
echo -e "${GREEN}3. IMPORTANT: Select THESE scopes (scroll down):${NC}"
echo ""
echo "   Under 'Select scopes' section, check these boxes:"
echo -e "   ${GREEN}✅ write:packages${NC}  ← MUST CHECK THIS!"
echo -e "   ${GREEN}✅ read:packages${NC}   ← MUST CHECK THIS!"
echo "   ✅ delete:packages  ← Optional"
echo ""
echo "   Also helpful (optional):"
echo "   ✅ repo (if image needs private repo access)"
echo ""
echo -e "${YELLOW}4. Scroll to bottom and click 'Generate token'${NC}"
echo ""
echo "5. COPY the token immediately (starts with 'ghp_...')"
echo "   You can't see it again!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Press ENTER when you have your NEW token ready..."
echo ""

# Logout first
echo "Logging out of previous session..."
docker logout ghcr.io 2>/dev/null || true
echo ""

# Get credentials
read -p "Enter your GitHub username: " GITHUB_USERNAME
echo ""
echo "Paste your NEW token (it won't show on screen):"
read -sp "Token: " GITHUB_TOKEN
echo ""
echo ""

# Validate token format
if [[ ! "$GITHUB_TOKEN" =~ ^ghp_ ]] && [[ ! "$GITHUB_TOKEN" =~ ^github_pat_ ]]; then
    echo -e "${RED}⚠️  Warning: Token doesn't start with 'ghp_' or 'github_pat_'${NC}"
    echo "Are you sure this is a GitHub Personal Access Token?"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Authenticating with GitHub Container Registry..."
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Success! Token Works!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "✅ You're now authenticated with GitHub Container Registry!"
    echo ""
    echo "🚀 Next step: Push your image"
    echo "   ./push-to-github.sh"
    echo ""
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ Authentication Still Failed${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Possible issues:"
    echo ""
    echo "1. Token scopes are STILL wrong"
    echo "   → Make sure you checked 'write:packages' AND 'read:packages'"
    echo ""
    echo "2. Wrong username"
    echo "   → Use your GitHub username, not email"
    echo ""
    echo "3. Token copied incorrectly"
    echo "   → Copy the entire token (usually 40+ characters)"
    echo ""
    echo "4. Token already expired"
    echo "   → Create a new one with longer expiration"
    echo ""
    echo "Need more help? Check:"
    echo "  https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry"
    echo ""
    exit 1
fi


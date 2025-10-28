#!/bin/bash

# ================================================================================
# GitHub Container Registry Setup Helper
# ================================================================================
# This script helps you create a Personal Access Token for GHCR
# No new account needed - uses your existing GitHub account!
# ================================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}GitHub Container Registry Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "✅ You already have a GitHub account!"
echo "✅ You're already in hyperscaledesignhub organization!"
echo ""
echo "You just need to create a Personal Access Token (PAT)"
echo ""

echo -e "${YELLOW}Step 1: Create Personal Access Token${NC}"
echo ""
echo "1. Open this URL in your browser:"
echo -e "   ${BLUE}https://github.com/settings/tokens/new${NC}"
echo ""
echo "2. Fill in the form:"
echo "   - Note: 'Docker Registry Access'"
echo "   - Expiration: '90 days' (or 'No expiration' for convenience)"
echo ""
echo "3. Select these scopes (checkboxes):"
echo "   ✅ write:packages"
echo "   ✅ read:packages"
echo "   ✅ delete:packages (optional)"
echo ""
echo "4. Click 'Generate token' at the bottom"
echo ""
echo "5. COPY the token (starts with 'ghp_...')"
echo "   You won't be able to see it again!"
echo ""
echo -e "${YELLOW}Step 2: Authenticate Docker${NC}"
echo ""

read -p "Press ENTER when you have your token ready..."
echo ""

read -p "Enter your GitHub username: " GITHUB_USERNAME
echo ""
read -sp "Paste your GitHub token (won't be visible): " GITHUB_TOKEN
echo ""
echo ""

echo "Authenticating with GitHub Container Registry..."
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "✅ You're authenticated with GitHub Container Registry!"
    echo ""
    echo "🚀 Next step: Push your image"
    echo "   cd $(pwd)"
    echo "   ./push-to-github.sh"
    echo ""
    
    # Save credentials info
    echo "📝 Your authentication is saved in Docker config"
    echo "   You won't need to login again unless you logout"
    echo ""
else
    echo ""
    echo "❌ Authentication failed!"
    echo ""
    echo "Common issues:"
    echo "  - Wrong username or token"
    echo "  - Token doesn't have 'write:packages' scope"
    echo "  - Token expired"
    echo ""
    echo "Try again or create a new token at:"
    echo "  https://github.com/settings/tokens/new"
    exit 1
fi


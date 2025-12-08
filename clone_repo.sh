#!/bin/bash
set -e

banner() {
    echo "================================================="
    echo "$1"
    echo "================================================="
}

error() {
    echo "❌ ERROR: $1"
    exit 1
}

warn() {
    echo "⚠ $1"
}

info() {
    echo "✓ $1"
}

# Check if cloning is enabled
CLONE_ON_START="${CLONE_ON_START:-true}"

if [ "$CLONE_ON_START" != "true" ]; then
    info "CLONE_ON_START is disabled - skipping repository clone"
    exit 0
fi

# Required environment variables
[ -z "$GITHUB_REPO_URL" ] && error "GITHUB_REPO_URL must be set (e.g., https://github.com/user/repo.git)"
[ -z "$GITHUB_TOKEN" ] && error "GITHUB_TOKEN must be set (GitHub Personal Access Token)"

# Extract repo name from URL (e.g., my-awesome-repo from https://github.com/user/my-awesome-repo.git)
REPO_NAME=$(echo "$GITHUB_REPO_URL" | sed 's|.*/\([^/]*\)\.git$|\1|' | sed 's|.*/\([^/]*\)$|\1|')

# Optional variables
PROJECT_DIR="${PROJECT_DIR:-/workspace/${REPO_NAME}}"

banner "GitHub Repository Setup"

# Parse the repo URL to extract owner/repo
REPO_URL_HTTPS="$GITHUB_REPO_URL"

# If the URL doesn't have https://, add it
if [[ ! "$REPO_URL_HTTPS" =~ ^https:// ]]; then
    REPO_URL_HTTPS="https://${REPO_URL_HTTPS}"
fi

# Construct URL with token for authentication
# Using token in URL: https://token@github.com/user/repo.git
AUTH_URL="${REPO_URL_HTTPS/https:\/\//https:\/\/${GITHUB_TOKEN}@}"

echo "Repository: $REPO_URL_HTTPS"
echo "Target directory: $PROJECT_DIR"

# Create parent directory if needed
mkdir -p "$(dirname "$PROJECT_DIR")"

# Check if repo already exists
if [ -d "$PROJECT_DIR/.git" ]; then
    warn "Repository already cloned at $PROJECT_DIR"
    info "Skipping clone. Use 'git pull' to update if needed."
    exit 0
fi

# Clone the repository
echo ""
echo "🔄 Cloning repository..."

if git clone "$AUTH_URL" "$PROJECT_DIR"; then
    info "Repository cloned successfully"
    
    # Display repo info
    echo ""
    echo "Repository Details:"
    cd "$PROJECT_DIR"
    echo "  URL: $(git config --get remote.origin.url | sed "s|https://[^@]*@|https://|")"
    echo "  Branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "  Commit: $(git rev-parse --short HEAD)"
    echo "  Author: $(git log -1 --pretty=format:'%an <%ae>')"
    
    # Try to run setup.sh if available
    echo ""
    if [ -f "setup.sh" ]; then
        echo "🔄 Attempting to run setup.sh..."
        if bash setup.sh 2>/dev/null; then
            info "Setup completed successfully with setup.sh"
        else
            warn "setup.sh failed - attempting alternative setup method..."
            # Try python setup.py if setup.sh failed
            if [ -f "setup.py" ] && python setup.py 2>/dev/null; then
                info "Setup completed successfully with python setup.py"
            else
                warn "setup.py failed or not available - continuing anyway"
            fi
        fi
    else
        echo "🔄 setup.sh not found - attempting python setup.py..."
        # Try python setup.py if setup.sh doesn't exist
        if [ -f "setup.py" ] && python setup.py 2>/dev/null; then
            info "Setup completed successfully with python setup.py"
        else
            warn "setup.py failed or not available - continuing anyway"
        fi
    fi
else
    error "Failed to clone repository. Check GITHUB_REPO_URL and GITHUB_TOKEN."
fi

echo ""

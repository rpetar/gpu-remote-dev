#!/bin/bash
set -e

# Cleanup function for partial clones
cleanup_on_error() {
        if [ -n "$1" ] && [ -d "$1" ]; then
                warn "Cleaning up partial clone at $1"
                rm -rf "$1"
        fi
}

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

# Run setup scripts with fallback logic
run_setup_scripts() {
        local setup_success=false
        
        # Try setup.sh first
        if [ -f "setup.sh" ]; then
                echo "🔄 Running setup.sh..."
                if bash setup.sh; then
                        info "Setup completed successfully with setup.sh"
                        setup_success=true
                        return 0
                else
                        warn "setup.sh failed (exit code: $?)"
                fi
        fi
        
        # Try setup.py with python3, then python
        if [ -f "setup.py" ]; then
                echo "🔄 Running setup.py..."
                local python_cmd=""
                if command -v python3 >/dev/null 2>&1; then
                        python_cmd="python3"
                elif command -v python >/dev/null 2>&1; then
                        python_cmd="python"
                fi
                
                if [ -n "$python_cmd" ] && $python_cmd setup.py; then
                        info "Setup completed successfully with $python_cmd setup.py"
                        setup_success=true
                        return 0
                else
                        warn "setup.py failed or python not available"
                fi
        fi
        
        if [ "$setup_success" = false ]; then
                warn "No setup scripts found or all setup attempts failed - continuing anyway"
        fi
        return 0
}

install_vscode_extensions() {
    local repo_root
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ext_file="$repo_root/.vscode/extensions.json"

    if ! command -v code >/dev/null 2>&1; then
        echo "VS Code CLI (code) not found; skipping extension install"
        return
    fi
    if [ ! -f "$ext_file" ]; then
        echo "No $ext_file found; skipping extension install"
        return
    fi

    # Parse recommendations
    local exts=()
    if command -v jq >/dev/null 2>&1; then
        mapfile -t exts < <(jq -r '.recommendations[]? // empty' "$ext_file")
    else
        # More robust fallback: read JSON properly even with newlines
        mapfile -t exts < <(grep -A 1000 '"recommendations"' "$ext_file" \
            | grep -oE '"[a-zA-Z0-9_.-]+\.[a-zA-Z0-9_.-]+"' \
            | tr -d '"' \
            | head -n 50)
    fi

    if [ "${#exts[@]}" -eq 0 ]; then
        echo "No recommendations found in $ext_file"
        return
    fi

    echo "Installing VS Code recommended extensions..."
    for ext in "${exts[@]}"; do
        echo "    -> $ext"
        code --install-extension "$ext"
    done
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
REPO_NAME="$(basename "${GITHUB_REPO_URL%.git}")"

# Optional variables
PROJECT_DIR="${PROJECT_DIR:-/workspace/${REPO_NAME}}"

banner "GitHub Repository Setup"

# Parse the repo URL to extract owner/repo
REPO_URL_HTTPS="$GITHUB_REPO_URL"

# If the URL doesn't have https://, add it
if [[ ! "$REPO_URL_HTTPS" =~ ^https:// ]]; then
        REPO_URL_HTTPS="https://${REPO_URL_HTTPS}"
fi

export GIT_TERMINAL_PROMPT=0

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

# Prepare askpass helper so the token never appears in argv/process list
ASKPASS_HELPER="$(mktemp)" || error "mktemp failed"
trap 'rm -f "$ASKPASS_HELPER"' EXIT
cat > "$ASKPASS_HELPER" <<'EOF'
#!/bin/sh
case "$1" in
Username*) printf "%s\n" "token" ;;
Password*) printf "%s\n" "${GITHUB_TOKEN:?GITHUB_TOKEN not set}" ;;
*) printf "%s\n" "${GITHUB_TOKEN:?GITHUB_TOKEN not set}" ;;
esac
EOF
chmod 700 "$ASKPASS_HELPER"

# Include a benign username in the URL; password is provided via askpass
REPO_URL_WITH_USER="${REPO_URL_HTTPS/https:\/\//https:\/\/token@}"

# Clone with error handling and cleanup
if ! GIT_ASKPASS="$ASKPASS_HELPER" GIT_TERMINAL_PROMPT=0 \
        git -c credential.helper= clone "$REPO_URL_WITH_USER" "$PROJECT_DIR" 2>&1; then
        cleanup_on_error "$PROJECT_DIR"
        error "Failed to clone repository. Check GITHUB_REPO_URL and GITHUB_TOKEN."
fi

info "Repository cloned successfully"

# Reset remote to clean URL (no username)
cd "$PROJECT_DIR" || error "Failed to enter $PROJECT_DIR"
git remote set-url origin "$REPO_URL_HTTPS"

# Display repo info
echo ""
echo "Repository Details:"
echo "    URL: $(git config --get remote.origin.url)"
echo "    Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "    Commit: $(git rev-parse --short HEAD)"
echo "    Author: $(git log -1 --pretty=format:'%an <%ae>')"

# Run setup scripts
echo ""
run_setup_scripts

# Install VS Code extensions
install_vscode_extensions

echo ""

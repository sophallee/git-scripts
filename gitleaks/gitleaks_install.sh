#!/bin/bash
set -euo pipefail  # Strict error handling

# Environment variables (uppercase allowed)
script_dir=$(dirname "$(realpath "$0")")
export PATH="$PATH:/usr/local/bin"

# Configuration (all lowercase)
gitleaks_repo="https://github.com/gitleaks/gitleaks.git"
install_dir="/usr/local/bin"
log_file="/var/log/gitleaks_install.log"
gitlab_installer_url="https://gitlab.com/gitlab-com/gl-security/security-research/gitleaks-endpoint-installer/-/raw/main/install.sh"
precommit_script="setup-pre-commit.sh"
gitleaks_custom_toml=".gitleaks.toml"
gitleaks_preconfig_yaml=".pre-commit-config.yaml"
gitleaks_config_files=("$script_dir/$gitleaks_preconfig_yaml" "$script_dir/$gitleaks_custom_toml")
git_template_dir="/usr/share/git-core/templates"

# Comma-delimited list of additional users (leave empty if none)
# additional_users="dev1,dev2""
additional_users=""
apply_system_wide=false

# Initialize logging
exec > >(tee -a "$log_file") 2>&1

# Function to log and exit on failure
fail() {
    echo -e "\n[ERROR] $1" >&2
    echo "Check $log_file for details" >&2
    exit 1
}

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
    fail "This script must be run as root. Try: sudo $0"
fi

# Verify files exists in script directory
files=("$precommit_script" "$gitleaks_custom_toml" "$gitleaks_preconfig_yaml")

for file_name in "${files[@]}"; do
    echo $file_name
    if [ ! -f "$script_dir/$file_name" ]; then
        fail "Required file $file_name not found in $script_dir"
    fi
done

if [ ! -f "$script_dir/$precommit_script" ]; then
    fail "Required file $precommit_script not found in $script_dir"
fi

if [ ! -f "$script_dir/$precommit_script" ]; then
    fail "Required file $precommit_script not found in $script_dir"
fi

# Get calling user info
original_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$(whoami)}")
home_dir=$(getent passwd "$original_user" | cut -d: -f6)
[ -z "$home_dir" ] && fail "Could not determine home directory for $original_user"

# Set temp_dir after home_dir is available
temp_dir="$home_dir/temp"

echo "=== Gitleaks Installation ==="
echo "User: $original_user"
echo "Home: $home_dir"
echo "Log: $log_file"
[ -n "$additional_users" ] && echo "Additional users: $additional_users"

# Install dependencies
echo -e "\n[1/4] Installing dependencies..."
dnf install -y golang make git python3-pip || fail "Failed to install dependencies"

# Setup user environment
echo -e "\n[2/4] Configuring user environment..."
if ! grep -q "\.local/bin" "$home_dir/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$home_dir/.bashrc"
fi

sudo -u "$original_user" mkdir -p "$temp_dir" || fail "Failed to create temp directory"

# Build gitleaks
echo -e "\n[3/4] Building gitleaks..."
gitleaks_dir="$temp_dir/gitleaks"

if [ ! -d "$gitleaks_dir" ]; then
    sudo -u "$original_user" git clone "$gitleaks_repo" "$gitleaks_dir" || 
        fail "Failed to clone repository"
fi

cd "$gitleaks_dir" || fail "Could not enter gitleaks directory"
sudo -u "$original_user" make build || fail "Build failed"

# Install system-wide
echo -e "\n[4/4] Installing system-wide..."
install -v -o root -g root -m 755 "$gitleaks_dir/gitleaks" "$install_dir" || 
    fail "Failed to install binary"

# Function to configure user-specific settings
configure_user() {
    local username="$1"
    echo -e "\nConfiguring user: $username"
    
    local user_home=$(getent passwd "$username" | cut -d: -f6)
    [ -z "$user_home" ] && { echo "Warning: Could not get home directory for $username, skipping"; return; }

    local user_temp="$user_home/temp"
    sudo -u "$username" mkdir -p "$user_temp" || { echo "Warning: Could not create temp dir for $username"; return; }

    # Install pre-commit
    echo "  Installing pre-commit..."
    sudo -u "$username" pip3 install --user pre-commit || 
        echo "Warning: Could not install pre-commit for $username" >&2

    # Install GitLab's gitleaks endpoint
    echo "  Installing GitLab gitleaks endpoint..."
    local installer_path="$user_temp/gitlab-gitleaks.install.sh"
    sudo -u "$username" curl -sSf "$gitlab_installer_url" -o "$installer_path" || 
        { echo "Warning: Failed to download GitLab installer for $username" >&2; return; }

    sudo -u "$username" chmod 700 "$installer_path"
    sudo -u "$username" sh -c "echo y | $installer_path" || 
        echo "Warning: GitLab gitleaks installation failed for $username" >&2
}

# Configure original user
configure_user "$original_user"

# Configure additional users if specified
if [ -n "$additional_users" ]; then
    IFS=',' read -ra users <<< "$additional_users"
    for user in "${users[@]}"; do
        id "$user" &>/dev/null || { echo "Warning: User $user does not exist, skipping"; continue; }
        configure_user "$user"
    done
fi

# Verify installation
if command -v gitleaks >/dev/null; then
    echo -e "\nInstallation successful!"
    echo "Gitleaks version: $(gitleaks --version)"
    echo "Binary installed to: $install_dir/gitleaks"
    echo "Configured for user: $original_user"
    [ -n "$additional_users" ] && echo "Additional configured users: $additional_users"
else
    fail "Installation verification failed"
fi

if [ $apply_system_wide = true ]; then

    # Deploy pre-commit setup script
    echo -e "\n[5/5] Deploying pre-commit setup system-wide..."

    # Copy the existing setup-pre-commit.sh to system location
    install -v -o root -g root -m 755 "$script_dir/$precommit_script" /usr/local/sbin/"$precommit_script" ||
        fail "Failed to install pre-commit setup script"

    # Add to /etc/skel/.bash_profile for new users
    mkdir -p /etc/skel
    touch /etc/skel/.bash_profile
    if ! grep -q "$precommit_script" /etc/skel/.bash_profile; then
        echo -e "\n# Auto-run pre-commit setup when entering project directories" >> /etc/skel/.bash_profile
        echo 'cd() { builtin cd "$@" && [ -f .pre-commit-config.yaml ] && /usr/local/sbin/setup-pre-commit.sh; }' >> /etc/skel/.bash_profile
    fi

    # Set up Git template directory for future clones
    sudo mkdir -p "$git_template_dir/hooks"
    sudo cp "${gitleaks_config_files[@]}" "$git_template_dir/"

    # Create post-checkout hook
sudo tee "$git_template_dir/hooks/post-checkout" >/dev/null <<'EOF'
#!/bin/sh
# Copies config files to new clones
gitleaks_config_files=(".pre-commit-config.yaml" ".gitleaks.toml")
repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$repo_root" ]; then
    for config in "${gitleaks_config_files[@]}"; do
        if [ -f "/usr/share/git-core/templates/$config" ] && [ ! -f "$repo_root/$config" ]; then
            cp "/usr/share/git-core/templates/$config" "$repo_root/"
        fi
    done
fi
EOF

    sudo chmod +x "$git_template_dir/hooks/post-checkout"
    sudo git config --system init.templateDir "$git_template_dir"

    echo "Repository cloned and configured successfully"
    echo "Future clones will automatically include the configuration files"
fi


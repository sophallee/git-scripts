#!/bin/bash
# Auto-installs pre-commit and cleans up after itself
gitlab_installer_url="https://gitlab.com/gitlab-com/gl-security/security-research/gitleaks-endpoint-installer/-/raw/main/install.sh"

# Install pre-commit for the user
cd ~ || exit 1
user_temp=~/temp
mkdir -p "$user_temp"

# Add ~/.local/bin to PATH if not already present
if ! grep -q "\.local/bin" ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

# Install pre-commit if not exists
if ! command -v pre-commit &>/dev/null; then
    echo "Installing pre-commit..."
    pip3 install --user pre-commit || python3 -m pip install --user pre-commit
fi

# Install GitLab's gitleaks endpoint
echo "Installing GitLab gitleaks endpoint..."
installer_path="$user_temp/gitlab-gitleaks.install.sh"
curl -sSf "$gitlab_installer_url" -o "$installer_path" || {
    echo "Warning: Failed to download GitLab installer" >&2
    exit 1
}

chmod 700 "$installer_path"
echo y | "$installer_path" || {
    echo "Warning: GitLab gitleaks installation failed" >&2
    exit 1
}

# Install pre-commit hooks if config exists
if [ -f .pre-commit-config.yaml ]; then
    echo "Installing pre-commit hooks..."
    pre-commit install || {
        echo "Warning: Failed to install pre-commit hooks" >&2
        exit 1
    }
fi

# Clean up .bash_profile first (remove the line that called this script)
sed -i '/setup-pre-commit\.sh/d' ~/.bash_profile

echo "Pre-commit setup completed successfully"
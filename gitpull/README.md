# Git Auto Pull Script Documentation
## Overview
The **Git Auto Pull** script automates the process of checking for updates in multiple Git repositories and pulling changes if updates are available.

It supports:
- Scanning all repositories within a given directory
- Skipping specified repositories
- Logging actions and results
- Debug logging for troubleshooting

---

## Dependencies
This script requires:
- **Bash** (version 4.0+ recommended)  
- **Git** (version 2.0+ recommended)

### Install Git (if not already installed)
#### On Debian/Ubuntu:
```
sudo apt update
sudo apt install git -y
```

#### On CentOS/RHEL/AlmaLinux/Fedora:
```bash
sudo dnf install git -y
```

#### On macOS:
```bash
brew install git
```

---

## Installation

1. **Save the script**
   Create a file named `git_auto_pull.sh` in your preferred scripts directory:
   ```bash
   nano ~/scripts/git_auto_pull.sh
   ```

2. **Make it executable**
   ```bash
   chmod +x ~/scripts/git_auto_pull.sh
   ```

3. **(Optional) Add to PATH**
   Add the script’s directory to your `PATH` so you can run it from anywhere:

   ```bash
   echo 'export PATH="$HOME/scripts:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

---

## Configuration

Edit the **Configuration** section at the top of the script:
```bash
development_dir="$HOME/development/github"  # Path to development folder
excluded_repos=("app2" "app3")              # Repositories to exclude
log_file="/tmp/git_auto_pull.log"           # Log file path
debug=true                                  # Enable verbose debugging
```
* **`development_dir`** — Path where your local Git repositories are stored. The script will scan all subfolders here.
* **`excluded_repos`** — List of repository names to skip.
* **`log_file`** — Path to the log file where script output will be saved.
* **`debug`** — Set to `true` for verbose logs; `false` for minimal logs.

---

## Usage

Run the script:
```bash
./git_auto_pull.sh
```

Example output (with debug enabled):
```
[2025-08-15 19:00:00] INFO: Starting repository update check
[2025-08-15 19:00:00] DEBUG: Scanning directory: /home/user/development/github
[2025-08-15 19:00:00] INFO: Checking my-repo...
[2025-08-15 19:00:00] DEBUG: Updates available (Local: 1a2b3c4 != Remote: 5d6e7f8)
[2025-08-15 19:00:00] INFO: Pulling updates for my-repo
[2025-08-15 19:00:01] INFO: Successfully updated my-repo
[2025-08-15 19:00:01] INFO: Update process completed
```

---

## How It Works

1. **Logging**
   * Logs are stored in `/tmp/git_auto_pull.log` by default.
   * Color-coded messages in the terminal for better readability.
   * Debug mode shows extra details about what the script is doing.

2. **Repository Scanning**
   * Iterates over each subdirectory in `development_dir`.
   * Skips any directories listed in `excluded_repos`.

3. **Update Check**
   * Runs `git remote update` to refresh remote branch data.
   * Compares the current branch’s local and remote commit hashes.
   * If different, pulls updates using `git pull --ff-only`.

---

## Automation (Optional)

You can schedule the script to run automatically using **cron**:

1. Edit the cron table:
   ```bash
   crontab -e
   ```
2. Add a job to run every day at 9 AM:
   ```bash
   0 9 * * * /home/user/scripts/git_auto_pull.sh >> /tmp/git_auto_pull_cron.log 2>&1
   ```
---

## Troubleshooting

* **Script doesn’t detect updates**
  Ensure you have the correct branch checked out and that `origin` is configured.

  ```bash
  git branch -vv
  ```

* **Pull fails with merge conflicts**
  The script uses `--ff-only` to prevent accidental merges. Resolve conflicts manually:

  ```bash
  git fetch origin
  git merge origin/main
  ```

* **Permission denied**
  Make sure the script is executable:

  ```bash
  chmod +x git_auto_pull.sh
  ```

---

## Security Notes

* Do not store this script in a publicly accessible location if you include sensitive repo paths.
* Make sure your Git credentials are managed securely (via SSH keys or credential managers).

---

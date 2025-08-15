# Gitleaks Installation Script Documentation

## File: `gitleaks_install.sh`

### Purpose

This script automates the installation and configuration of [Gitleaks](https://github.com/gitleaks/gitleaks) from source, sets up **pre-commit** integration, and optionally applies a **system-wide** configuration for all future Git repositories.

---

## Features

* Installs required dependencies (Go, Make, Git, Python pip).
* Clones and builds Gitleaks from the official repository.
* Installs the binary to `/usr/local/bin`.
* Installs and configures `pre-commit` hooks for one or more users.
* Downloads and installs GitLab's Gitleaks Endpoint Installer.
* Supports **custom Gitleaks rules** via `.gitleaks.toml`.
* Optionally configures system-wide Git templates and hooks.

---

## Requirements

* Root privileges (`sudo` access).
* RHEL/Fedora/CentOS-based system with `dnf` package manager.
* Internet access.

---

## Script Variables

| Variable                  | Description                                  | Default                                      |
| ------------------------- | -------------------------------------------- | -------------------------------------------- |
| `gitleaks_repo`           | Gitleaks GitHub repo URL                     | `https://github.com/gitleaks/gitleaks.git`   |
| `install_dir`             | Install location for Gitleaks binary         | `/usr/local/bin`                             |
| `log_file`                | Installation log file                        | `/var/log/gitleaks_install.log`              |
| `gitlab_installer_url`    | GitLab Gitleaks endpoint installer URL       | GitLab security-research repo                |
| `precommit_script`        | Pre-commit setup script name                 | `setup-pre-commit.sh`                        |
| `gitleaks_custom_toml`    | Custom Gitleaks rules file name              | `.gitleaks.toml`                             |
| `gitleaks_preconfig_yaml` | Pre-commit configuration file name           | `.pre-commit-config.yaml`                    |
| `gitleaks_config_files`   | Array of config files for Git templates      | `.pre-commit-config.yaml` & `.gitleaks.toml` |
| `git_template_dir`        | Git template directory for system-wide hooks | `/usr/share/git-core/templates`              |
| `additional_users`        | Comma-separated usernames to configure       | *(empty)*                                    |
| `apply_system_wide`       | Apply system-wide config if `true`           | `false`                                      |

---

## Included Files

### 1. `.gitleaks.toml`

Custom rules extending Gitleaks defaults. Detects:

* Hardcoded passwords
* API keys
* Database connection strings
* Bearer tokens
* Generic secret patterns
* Short but sensitive values (PINs, passcodes)

---

### 2. `.pre-commit-config.yaml`

Defines Gitleaks as a `pre-commit` hook:

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.2
    hooks:
      - id: gitleaks
```

---

### 3. `setup-pre-commit.sh`

User-level helper script to:

* Install `pre-commit` locally.
* Install GitLab’s Gitleaks endpoint.
* Run `pre-commit install` if `.pre-commit-config.yaml` is present.
* Remove itself from `.bash_profile` after execution.

---

## Installation

### 1. Prepare Files

Place the following in the same directory:

```
gitleaks_install.sh
setup-pre-commit.sh
.gitleaks.toml
.pre-commit-config.yaml
```

---

### 2. Run Installation

```bash
sudo ./gitleaks_install.sh
```

---

### 3. Configure Additional Users

Edit inside `gitleaks_install.sh`:

```bash
additional_users="dev1,dev2"
```

Run the script again.

---

### 4. Apply System-wide Configuration

Edit inside `gitleaks_install.sh`:

```bash
apply_system_wide=true
```

This will:

* Install `setup-pre-commit.sh` to `/usr/local/sbin/`.
* Modify `/etc/skel/.bash_profile` to auto-run setup for new users.
* Configure Git templates so all new clones include `.gitleaks.toml` and `.pre-commit-config.yaml`.

---

## Verification

After installation:

```bash
gitleaks --version
```

Should output the installed Gitleaks version and confirm the binary location.

---

## Logs

Installation logs are stored at:

```
/var/log/gitleaks_install.log
```

---

## Uninstallation

1. Remove binary:

   ```bash
   sudo rm -f /usr/local/bin/gitleaks
   ```
2. Remove Git template directory configuration (if system-wide applied):

   ```bash
   sudo git config --system --unset init.templateDir
   ```

---

## Example Usage

Run a scan manually:

```bash
gitleaks detect
```

Commit code in a repository — `pre-commit` will automatically run Gitleaks before committing.

---

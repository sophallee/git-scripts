# Git Repository Sync with Commit Mapping (v2.1)

## Overview

`git_sync.sh` synchronizes commits between **source** and **target** Git repositories while recording a mapping of **source commit hashes** to **target commit hashes** in a local SQLite database.

Key features:

* Avoids duplicating commits already synced.
* Preserves commit metadata (message, author, date).
* Handles **initial commits** differently from normal commits.
* Supports repository exclusion.
* Optionally pushes changes automatically to the target repository.
* Provides detailed logging with configurable levels.

---

## Files

### 1. `env.template`

Environment variable template for `.env` configuration.

| Variable          | Description                                                           | Default                                   |
| ----------------- | --------------------------------------------------------------------- | ----------------------------------------- |
| `base_dir_source` | Path to base directory containing **source** repositories             | `$HOME/development`                       |
| `base_dir_dest`   | Path to base directory containing **destination** repositories        | `$HOME/development`                       |
| `excluded_repos`  | Space-separated list of repository names to exclude from syncing      | *(empty)*                                 |
| `db_file`         | Path to SQLite database file for commit mapping                       | `git-sync-mapping.db` in script directory |
| `auto_push`       | Automatically push to target repository after sync (`true` / `false`) | `true`                                    |
| `log_dir`         | Directory to store log files                                          | `/var/log/gitsync`                        |
| `max_log_files`   | Maximum number of old log files to keep                               | `30`                                      |
| `log_level`       | Logging level (`DEBUG`, `INFO`, `WARNING`, `ERROR`)                   | `INFO`                                    |

---

### 2. `git_sync.sh`

Main script functionality:

1. Loads `.env` (if present) and sets default values.
2. Initializes SQLite database schema.
3. Lists available repositories if no arguments are passed.
4. Synchronizes commits from a **source** repository to a **target** repository.
5. Handles auto-push if enabled.

---

## Database Schema

The SQLite database (`db_file`) stores commit mappings:

| Column           | Description                        |
| ---------------- | ---------------------------------- |
| `source_repo`    | Absolute path of source repository |
| `target_repo`    | Absolute path of target repository |
| `source_hash`    | Commit hash in source repository   |
| `target_hash`    | Commit hash in target repository   |
| `source_message` | Original commit message            |
| `source_author`  | Commit author name & email         |
| `source_date`    | Original commit date               |
| `sync_time`      | Timestamp when commit was synced   |

Indexes:

* `idx_target` on `(target_repo, target_hash)`
* `idx_source` on `(source_repo, source_hash)`

---

## Key Functions

### **init\_logging**

* Creates log directory (`log_dir`) or falls back to `script_dir/logs`.
* Rotates old logs based on `max_log_files`.
* Logs messages to timestamped files with levels: `DEBUG`, `INFO`, `WARNING`, `ERROR`.

### **init\_db**

* Creates SQLite database and `commit_mapping` table if it doesn't exist.
* Adds indexes for faster queries.

### **is\_commit\_synced**

* Checks if a commit hash from the source repo is already in the database.

### **record\_commit\_mapping**

* Records a new commit mapping with metadata in the SQLite database.

### **get\_commit\_metadata**

* Retrieves commit hash, author, date, and message for a given commit.

### **get\_repo\_commits**

* Lists all commit hashes in chronological order for the source repository.

### **list\_and\_sync\_all\_repos**

* Iterates over all repositories in `base_dir_source`.
* Skips excluded repositories.
* Calls `sync_repository` for each valid repository.
* Provides a summary of processed, synced, and skipped repositories.

### **sync\_repository**

* Validates source and target repositories.
* Pulls latest changes from both repositories.
* Loops through all commits in the source repository:

  * Skips commits already synced.
  * Creates patch files using `git format-patch`.
  * Applies patches to target repository using `git am --committer-date-is-author-date`.
  * Records commit mappings in the SQLite database.
* Cleans up temporary files.
* Auto-pushes changes if `auto_push=true`.

---

## Usage

### 1. Prepare `.env` file

Copy `env.template` to `.env` and adjust values:

```bash
cp env.template .env
nano .env
```

Example:

```env
base_dir_source="/home/user/projects/source"
base_dir_dest="/home/user/projects/dest"
excluded_repos="test-repo old-repo"
db_file="/home/user/git-sync/git-sync-mapping.db"
auto_push=true
log_dir="/var/log/gitsync"
max_log_files=30
log_level=DEBUG
```

---

### 2. List available repositories

```bash
./git_sync.sh
```

Output example:

```
Available repositories in /home/user/projects/source:
----------------------------------------
- repo1
- repo2
Excluded repositories: test-repo old-repo
```

---

### 3. Sync repositories

#### Same source and target name:

```bash
./git_sync.sh repo1
```

#### Different target name:

```bash
./git_sync.sh repo1 repo1-mirror
```

---

### 4. Verify synced commits

Check the database:

```bash
sqlite3 git-sync-mapping.db "SELECT * FROM commit_mapping LIMIT 5;"
```

---

### 5. Logging

* Logs are stored in `log_dir` with timestamped filenames.
* Controlled by `log_level`.
* Example levels:

  * `DEBUG` – detailed internal information
  * `INFO` – normal operational messages
  * `WARNING` – non-fatal issues
  * `ERROR` – fatal or failed operations

---

## Notes

* Requires **Git** and **SQLite3** installed.
* Commits are skipped if already recorded in the mapping database.
* Handles initial commits (`--root`) separately.
* Auto-push can be disabled by setting `auto_push=false`.
* Repository exclusion prevents syncing specific repositories.
* Temporary patch files are cleaned after each repository sync.

---

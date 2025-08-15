Here’s full **Markdown documentation** for `env.template` and `git_sync.sh` based exactly on your script’s logic.

---

# Git Repository Sync with Commit Mapping

## Overview

The `git_sync.sh` script synchronizes commits between two Git repositories while recording a mapping of **source commit hashes** to **target commit hashes** in a local SQLite database.
It is designed to:

* Avoid duplicating commits that are already synced.
* Preserve commit metadata (message, author, date).
* Handle **initial commits** differently from normal commits.
* Optionally skip repositories.
* Provide a quick list of available repositories for syncing.

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

---

### 2. `git_sync.sh`

Main script that:

1. Loads `.env` (if present).
2. Sets default values for missing variables.
3. Initializes SQLite database schema.
4. Lists available repositories if no arguments are passed.
5. Syncs commits from a **source** repository to a **target** repository.

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

### **init\_db**

Initializes the SQLite database and creates necessary tables/indexes.

### **is\_commit\_synced**

Checks if a specific commit from the source repo has already been synced.

### **record\_commit\_mapping**

Adds a commit mapping record to the database.

### **get\_commit\_metadata**

Retrieves commit hash, author name, author email, commit date, and commit message for a given commit.

### **get\_repo\_commits**

Lists all commit hashes in chronological order.

### **list\_available\_repos**

Prints all available repositories in the `base_dir_source`, excluding those in `excluded_repos`.

### **sync\_repository**

Main sync logic:

1. Validates input repositories.
2. Pulls latest changes from both source and target.
3. Iterates over commits in the source repo.
4. Skips commits already synced.
5. Generates patch files (`git format-patch`).
6. Applies patches to the target repo (`git am`).
7. Records mapping in database.
8. Cleans up temporary files.

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
```

---

### 2. List available repositories

```bash
./git_sync.sh
```

Example output:

```
Available repositories in /home/user/projects/source:
----------------------------------------
- repo1
- repo2

To sync a repository:
  ./git_sync.sh <repository_name> [target_repository_name]

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

### 4. Verify sync

Check the database:

```bash
sqlite3 git-sync-mapping.db "SELECT * FROM commit_mapping LIMIT 5;"
```

---

## Example Flow

1. You have:

   * `/src/repo1` (source)
   * `/mirror/repo1` (target)
2. Run:

   ```bash
   ./git_sync.sh repo1
   ```
3. Script:

   * Updates both repos with `git pull`.
   * Loops through each commit in `repo1`.
   * Skips commits already in `git-sync-mapping.db`.
   * Creates patches and applies them to `repo1` in the target directory.
   * Records commit mappings.
4. Push target repo (if `auto_push=true`, script can be extended to do this automatically).

---

## Notes

* Requires **SQLite** and **Git** installed.
* Only commits not already in mapping DB will be synced.
* If a patch fails, the script aborts with `git am --abort`.
* Initial commits are handled with `--root` patches.
* `excluded_repos` prevents syncing certain repositories.

---

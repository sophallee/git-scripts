#!/bin/bash
# Git Repository Sync with Commit ID Mapping
# Version 2.1 - Database in script directory with auto-push

# Configuration
# ------------------------------------------------------------------------------
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging configuration
log_dir="/var/log/gitsync"
log_file="$log_dir/gitsync.log"
mkdir -p "$log_dir"
touch "$log_file"

# Function to log messages
log() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$log_file"
    if [ "$level" == "ERROR" ]; then
        echo "$message" >&2
    elif [ "$level" != "DEBUG" ]; then
        echo "$message"
    fi
}

# Load .env file if exists
if [ -f "$script_dir/.env" ]; then
    set -a
    source "$script_dir/.env" || { log "ERROR" "failed to load .env file"; exit 1; }
    set +a
fi

# Set default values (environment variables remain uppercase)
# Set default values (all lowercase, only HOME is environment variable)
base_dir_source="${base_dir_source:-$HOME/development}"
base_dir_dest="${base_dir_dest:-$HOME/development}"
excluded_repos="${excluded_repos:-}"
db_file="${db_file:-$script_dir/git-sync-mapping.db}"  # Now in script directory
auto_push="${auto_push:-true}"  # Default to auto-push
log_dir="${log_dir:-/var/log/gitsync}"
max_log_files="${max_log_files:-30}"  # Number of old log files to keep
log_level="${log_level:-INFO}"  # DEBUG, INFO, WARNING, ERROR
# Initialize SQLite Database
# ------------------------------------------------------------------------------

init_db() {
    log "INFO" "initializing database at $db_file"
    sqlite3 "$db_file" <<EOF
    CREATE TABLE IF NOT EXISTS commit_mapping (
        source_repo    TEXT NOT NULL,
        target_repo    TEXT NOT NULL,
        source_hash    TEXT NOT NULL,
        target_hash    TEXT NOT NULL,
        source_message TEXT NOT NULL,
        source_author  TEXT NOT NULL,
        source_date    TEXT NOT NULL,
        sync_time      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (source_repo, target_repo, source_hash)
    );
    CREATE INDEX IF NOT EXISTS idx_target ON commit_mapping(target_repo, target_hash);
    CREATE INDEX IF NOT EXISTS idx_source ON commit_mapping(source_repo, source_hash);
EOF
    if [ $? -ne 0 ]; then
        log "ERROR" "failed to initialize database"
        return 1
    fi
    log "INFO" "database initialized successfully"
}

# Database Functions
# ------------------------------------------------------------------------------

is_commit_synced() {
    local source_repo=$1
    local commit_hash=$2
    sqlite3 "$db_file" \
        "SELECT COUNT(*) FROM commit_mapping 
         WHERE source_repo='$source_repo' AND source_hash='$commit_hash';"
}

record_commit_mapping() {
    local source_repo=$1
    local target_repo=$2
    local source_hash=$3
    local target_hash=$4
    local message=$5
    local author=$6
    local date=$7

    # Escape single quotes for SQL
    message=${message//\'/''}
    author=${author//\'/''}

    sqlite3 "$db_file" <<EOF
    INSERT INTO commit_mapping (
        source_repo, target_repo, 
        source_hash, target_hash,
        source_message, source_author, source_date
    ) VALUES (
        '$source_repo', '$target_repo',
        '$source_hash', '$target_hash',
        '$message', '$author', '$date'
    );
EOF
    if [ $? -ne 0 ]; then
        log "ERROR" "failed to record commit mapping for $source_hash"
        return 1
    fi
    log "INFO" "recorded commit mapping: $source_hash -> $target_hash"
}

# Git Helper Functions
# ------------------------------------------------------------------------------

get_commit_metadata() {
    local repo=$1
    local commit=$2
    cd "$repo" || return 1
    git show -s --format="%H%n%an%n%ae%n%ad%n%B" "$commit" 2>/dev/null
}

get_repo_commits() {
    local repo=$1
    cd "$repo" || return 1
    git log --pretty=format:%H --reverse
}

# Repository Listing
# ------------------------------------------------------------------------------

list_and_sync_all_repos() {
    log "INFO" "starting sync of all repositories in $base_dir_source"
    log "INFO" "excluded repositories: ${excluded_repos}"
    
    IFS=' ' read -ra excluded <<< "$excluded_repos"
    found=0
    synced=0
    skipped=0
    
    for repo in "$base_dir_source"/*; do
        if [ -d "$repo/.git" ]; then
            repo_name=$(basename "$repo")
            
            # Check if repo is excluded
            should_skip=0
            for excluded_repo in "${excluded[@]}"; do
                if [ "$repo_name" == "$excluded_repo" ]; then
                    should_skip=1
                    break
                fi
            done
            
            if [ "$should_skip" -eq 1 ]; then
                log "INFO" "skipping excluded repository: $repo_name"
                skipped=$((skipped + 1))
                continue
            fi
            
            log "INFO" "syncing repository: $repo_name"
            if sync_repository "$repo_name"; then
                synced=$((synced + 1))
                log "INFO" "successfully synced: $repo_name"
            else
                log "ERROR" "failed to sync: $repo_name"
            fi
            found=$((found + 1))
        fi
    done
    
    log "INFO" "sync summary: found $found repositories, successfully synced $synced, skipped $skipped"
    if [ "$found" -eq 0 ]; then
        log "WARNING" "no repositories found in $base_dir_source"
    fi
}

# Main Sync Function
# ------------------------------------------------------------------------------

sync_repository() {
    local source_repo_name=$1
    local target_repo_name=${2:-$source_repo_name}

    # Check if source repo is excluded
    IFS=' ' read -ra excluded <<< "$excluded_repos"
    for excluded_repo in "${excluded[@]}"; do
        if [ "$source_repo_name" == "$excluded_repo" ]; then
            log "ERROR" "repository '$source_repo_name' is excluded from syncing"
            return 1
        fi
    done

    local source_repo="$base_dir_source/$source_repo_name"
    local target_repo="$base_dir_dest/$target_repo_name"
    local temp_dir=$(mktemp -d -t git-sync-XXXXXX)

    log "INFO" "syncing from: $source_repo"
    log "INFO" "syncing to: $target_repo"
    log "INFO" "using temp dir: $temp_dir"

    # Validate repositories
    if [ ! -d "$source_repo/.git" ]; then
        log "ERROR" "source repository $source_repo is not a valid git repository"
        return 1
    fi

    if [ ! -d "$target_repo/.git" ]; then
        log "ERROR" "target repository $target_repo is not a valid git repository"
        return 1
    fi

    # Update repositories
    log "INFO" "updating repositories..."
    (cd "$source_repo" && git pull >> "$log_file" 2>&1) || {
        log "ERROR" "failed to update source repository $source_repo"
        return 1
    }
    (cd "$target_repo" && git pull >> "$log_file" 2>&1) || {
        log "ERROR" "failed to update target repository $target_repo"
        return 1
    }

    # Get all source commits
    log "INFO" "analyzing commit history..."
    mapfile -t source_commits < <(get_repo_commits "$source_repo")

    processed=0
    skipped=0

    for source_commit in "${source_commits[@]}"; do
        # Skip if already synced
        if [ "$(is_commit_synced "$source_repo" "$source_commit")" -gt 0 ]; then
            log "INFO" "already synced: ${source_commit:0:7}"
            skipped=$((skipped + 1))
            continue
        fi

        log "INFO" "processing commit: ${source_commit:0:7}"
        
        # Get commit metadata
        mapfile -t metadata < <(get_commit_metadata "$source_repo" "$source_commit")
        author="${metadata[1]} <${metadata[2]}>"
        date="${metadata[3]}"
        message="${metadata[*]:4}"
        
        # Create patch file - handle initial commit differently
        if (cd "$source_repo" && git rev-list --count "$source_commit" 2>/dev/null) | grep -q '^1$'; then
            # This is the initial commit
            (cd "$source_repo" && \
             git format-patch --root --stdout "$source_commit" > "$temp_dir/$source_commit.patch")
        else
            # Normal commit with parent
            (cd "$source_repo" && \
             git format-patch --stdout "$source_commit^..$source_commit" > "$temp_dir/$source_commit.patch")
        fi
        
        # Apply patch to target
        if (cd "$target_repo" && git am --committer-date-is-author-date "$temp_dir/$source_commit.patch" >> "$log_file" 2>&1); then
            # Get new commit hash
            target_commit=$(cd "$target_repo" && git rev-parse HEAD)
            
            # Record mapping
            record_commit_mapping \
                "$source_repo" "$target_repo" \
                "$source_commit" "$target_commit" \
                "$message" "$author" "$date"
            
            processed=$((processed + 1))
            log "INFO" "successfully processed commit ${source_commit:0:7} -> ${target_commit:0:7}"
        else
            log "ERROR" "failed to apply patch for ${source_commit:0:7}"
            (cd "$target_repo" && git am --abort >> "$log_file" 2>&1)
            return 1
        fi
    done

    # Clean up
    rm -rf "$temp_dir"

    log "INFO" "sync complete for $source_repo_name: processed $processed commits, skipped $skipped"

    # Auto-push if enabled
    if [ "$auto_push" = "true" ]; then
        log "INFO" "pushing changes to target repository..."
        if (cd "$target_repo" && git push >> "$log_file" 2>&1); then
            log "INFO" "successfully pushed changes to target repository"
        else
            log "ERROR" "failed to push changes to target repository"
            return 1
        fi
    else
        log "INFO" "auto-push is disabled, changes not pushed to remote"
    fi
    
    return 0
}

# Main Execution
# ------------------------------------------------------------------------------

# Set up log rotation configuration
if [ ! -f "/etc/logrotate.d/gitsync" ]; then
    log "INFO" "creating logrotate configuration for gitsync"
    sudo tee "/etc/logrotate.d/gitsync" > /dev/null <<EOF
$log_file {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 root adm
}
EOF
fi

init_db

# Validate base directories
if [ ! -d "$base_dir_source" ]; then
    log "ERROR" "source base directory not found: $base_dir_source"
    exit 1
fi

if [ ! -d "$base_dir_dest" ]; then
    log "ERROR" "destination base directory not found: $base_dir_dest"
    exit 1
fi

# Show repository list if no arguments
if [ "$#" -eq 0 ]; then
    list_and_sync_all_repos
    exit 0
fi

# Start sync for specific repository
sync_repository "$1" "$2"
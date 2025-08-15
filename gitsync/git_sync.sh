#!/bin/bash
# Git Repository Sync with Commit ID Mapping
# Version 2.1 - Database in script directory with auto-push

# Configuration
# ------------------------------------------------------------------------------
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env file if exists
if [ -f "$script_dir/.env" ]; then
    set -a
    source "$script_dir/.env" || { echo "Error: Failed to load .env file" >&2; exit 1; }
    set +a
fi

# Set default values
base_dir_source="${base_dir_source:-$HOME/development}"
base_dir_dest="${base_dir_dest:-$HOME/development}"
excluded_repos="${excluded_repos:-}"
db_file="${db_file:-$script_dir/git-sync-mapping.db}"  # Now in script directory
auto_push="${auto_push:-true}"  # Default to auto-push
log_dir="${log_dir:-/var/log/gitsync}"
max_log_files="${max_log_files:-30}"  # Number of old log files to keep
log_level="${log_level:-INFO}"  # DEBUG, INFO, WARNING, ERROR

 Logging Implementation
# ------------------------------------------------------------------------------

init_logging() {
    # Create log directory if it doesn't exist
    sudo mkdir -p "$log_dir" 2>/dev/null || {
        echo "Warning: Failed to create log directory $log_dir, falling back to $script_dir/logs" >&2
        log_dir="$script_dir/logs"
        mkdir -p "$log_dir"
    }

    # Set appropriate permissions
    sudo chown "$(whoami)" "$log_dir" 2>/dev/null || true
    chmod 755 "$log_dir"

    log_file="$log_dir/gitsync_$(date +%Y%m%d_%H%M%S).log"
    touch "$log_file"
    chmod 644 "$log_file"

    # Rotate old logs
    find "$log_dir" -name "gitsync_*.log" -type f | sort -r | tail -n +$((max_log_files + 1)) | xargs rm -f 2>/dev/null
}

log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Check if the message's level is at or above the configured log level
    case $log_level in
        DEBUG) ;;
        INFO) [[ $level == "DEBUG" ]] && return ;;
        WARNING) [[ $level == "DEBUG" || $level == "INFO" ]] && return ;;
        ERROR) [[ $level != "ERROR" ]] && return ;;
    esac

    echo "[$timestamp] [$level] $message" | tee -a "$log_file"
}

# Initialize logging
init_logging

log "INFO" "Starting git-sync script"
log "DEBUG" "Script directory: $script_dir"
log "DEBUG" "Configuration loaded:"
log "DEBUG" "  base_dir_source: $base_dir_source"
log "DEBUG" "  base_dir_dest: $base_dir_dest"
log "DEBUG" "  excluded_repos: $excluded_repos"
log "DEBUG" "  auto_push: $auto_push"
log "DEBUG" "  log_dir: $log_dir"
log "DEBUG" "  log_level: $log_level"

# Initialize SQLite Database
# ------------------------------------------------------------------------------

init_db() {
    log "DEBUG" "Initializing database at $db_file"
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
    log "DEBUG" "Database initialized"
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

    log "DEBUG" "Recording commit mapping: $source_repo:$source_hash -> $target_repo:$target_hash"
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
    log "INFO" "Starting sync of all repositories in $base_dir_source"
    log "INFO" "Excluded repositories: ${excluded_repos}"
    
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
                log "INFO" "Skipping excluded repository: $repo_name"
                skipped=$((skipped + 1))
                continue
            fi
            
            log "INFO" "Syncing repository: $repo_name"
            if sync_repository "$repo_name"; then
                log "INFO" "Successfully synced: $repo_name"
                synced=$((synced + 1))
            else
                log "ERROR" "Failed to sync: $repo_name"
            fi
            found=$((found + 1))
        fi
    done
    
    log "INFO" "Sync summary: Found $found repositories, Synced repository: $synced, Skipped commits: $skipped"
    echo ""
    echo "Sync completed. Details logged to $log_file"
    echo "Found repositories: $found"
    echo "Successfully synced: $synced"
    echo "Skipped (excluded): $skipped"
}

# Main Sync Function
# ------------------------------------------------------------------------------

sync_repository() {
    local source_repo_name=$1
    local target_repo_name=${2:-$source_repo_name}

    log "INFO" "Starting sync for repository: $source_repo_name -> $target_repo_name"

    # Check if source repo is excluded
    IFS=' ' read -ra excluded <<< "$excluded_repos"
    for excluded_repo in "${excluded[@]}"; do
        if [ "$source_repo_name" == "$excluded_repo" ]; then
            log "ERROR" "Repository '$source_repo_name' is excluded from syncing"
            return 1
        fi
    done

    local source_repo="$base_dir_source/$source_repo_name"
    local target_repo="$base_dir_dest/$target_repo_name"
    local temp_dir=$(mktemp -d -t git-sync-XXXXXX)

    log "DEBUG" "Source repo path: $source_repo"
    log "DEBUG" "Target repo path: $target_repo"
    log "DEBUG" "Temp dir: $temp_dir"

    # Validate repositories
    if [ ! -d "$source_repo/.git" ]; then
        log "ERROR" "Source repository $source_repo is not a valid Git repository"
        return 1
    fi

    if [ ! -d "$target_repo/.git" ]; then
        log "ERROR" "Target repository $target_repo is not a valid Git repository"
        return 1
    fi

    # Update repositories
    log "INFO" "Updating repositories..."
    (cd "$source_repo" && git pull) || {
        log "ERROR" "Failed to pull source repository $source_repo"
        return 1
    }
    (cd "$target_repo" && git pull) || {
        log "ERROR" "Failed to pull target repository $target_repo"
        return 1
    }

    # Get all source commits
    log "INFO" "Analyzing commit history..."
    mapfile -t source_commits < <(get_repo_commits "$source_repo")

    processed=0
    skipped=0

    for source_commit in "${source_commits[@]}"; do
        # Skip if already synced
        if [ "$(is_commit_synced "$source_repo" "$source_commit")" -gt 0 ]; then
            log "DEBUG" "Commit already synced: ${source_commit:0:7}"
            skipped=$((skipped + 1))
            continue
        fi

        log "INFO" "Processing commit: ${source_commit:0:7}"
        
        # Get commit metadata
        mapfile -t metadata < <(get_commit_metadata "$source_repo" "$source_commit")
        author="${metadata[1]} <${metadata[2]}>"
        date="${metadata[3]}"
        message="${metadata[*]:4}"
        
        # Create patch file
        if (cd "$source_repo" && git rev-list --count "$source_commit" 2>/dev/null) | grep -q '^1$'; then
            log "DEBUG" "Processing initial commit"
            (cd "$source_repo" && \
             git format-patch --root --stdout "$source_commit" > "$temp_dir/$source_commit.patch") || {
                log "ERROR" "Failed to create patch for initial commit ${source_commit:0:7}"
                return 1
            }
        else
            log "DEBUG" "Processing normal commit"
            (cd "$source_repo" && \
             git format-patch --stdout "$source_commit^..$source_commit" > "$temp_dir/$source_commit.patch") || {
                log "ERROR" "Failed to create patch for commit ${source_commit:0:7}"
                return 1
            }
        fi
        
        # Apply patch to target
        if (cd "$target_repo" && git am --committer-date-is-author-date "$temp_dir/$source_commit.patch"); then
            # Get new commit hash
            target_commit=$(cd "$target_repo" && git rev-parse HEAD)
            
            # Record mapping
            record_commit_mapping \
                "$source_repo" "$target_repo" \
                "$source_commit" "$target_commit" \
                "$message" "$author" "$date"
            
            log "INFO" "Successfully applied commit ${source_commit:0:7} -> ${target_commit:0:7}"
            processed=$((processed + 1))
        else
            log "ERROR" "Failed to apply patch for commit ${source_commit:0:7}"
            (cd "$target_repo" && git am --abort)
            return 1
        fi
    done

    # Clean up
    rm -rf "$temp_dir"

    log "INFO" "Sync complete for $source_repo_name: Processed $processed commits, Skipped $skipped commits"

    # Auto-push if enabled
    if [ "$auto_push" = "true" ]; then
        log "INFO" "Pushing changes to target repository..."
        if (cd "$target_repo" && git push); then
            log "INFO" "Successfully pushed changes to target repository"
        else
            log "ERROR" "Failed to push changes to target repository"
            return 1
        fi
    else
        log "INFO" "Auto-push is disabled - changes not pushed"
    fi
    
    return 0
}

# Main Execution
# ------------------------------------------------------------------------------

init_db

# Validate base directories
if [ ! -d "$base_dir_source" ]; then
    log "ERROR" "Source base directory not found: $base_dir_source"
    exit 1
fi

if [ ! -d "$base_dir_dest" ]; then
    log "ERROR" "Destination base directory not found: $base_dir_dest"
    exit 1
fi

# Show repository list if no arguments
if [ "$#" -eq 0 ]; then
    list_and_sync_all_repos
    exit 0
fi

# Start sync for specific repository
sync_repository "$1" "$2"
exit $?
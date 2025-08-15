#!/bin/bash
# Git Repository Sync with Commit ID Mapping
# Version 2.0 - Database in script directory

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


# Initialize SQLite Database
# ------------------------------------------------------------------------------

init_db() {
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

list_available_repos() {
    echo "Available repositories in $base_dir_source:"
    echo "----------------------------------------"
    
    IFS=' ' read -ra excluded <<< "$excluded_repos"
    found=0
    for repo in "$base_dir_source"/*; do
        if [ -d "$repo/.git" ]; then
            repo_name=$(basename "$repo")
            
            skip=0
            for excluded_repo in "${excluded[@]}"; do
                if [ "$repo_name" == "$excluded_repo" ]; then
                    skip=1
                    break
                fi
            done
            
            if [ "$skip" -eq 0 ]; then
                echo "- $repo_name"
                found=$((found + 1))
            fi
        fi
    done
    
    if [ "$found" -eq 0 ]; then
        echo "No repositories found (excluding: ${excluded_repos})"
    else
        echo ""
        echo "To sync a repository:"
        echo "  $0 <repository_name> [target_repository_name]"
        echo ""
        echo "Excluded repositories: ${excluded_repos}"
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
            echo "Error: Repository '$source_repo_name' is excluded from syncing" >&2
            exit 1
        fi
    done

    local source_repo="$base_dir_source/$source_repo_name"
    local target_repo="$base_dir_dest/$target_repo_name"
    local temp_dir=$(mktemp -d -t git-sync-XXXXXX)

    echo "Syncing from: $source_repo"
    echo "Syncing to:   $target_repo"
    echo "Mapping DB:   $db_file"
    echo "Temp dir:     $temp_dir"

    # Validate repositories
    if [ ! -d "$source_repo/.git" ]; then
        echo "Error: Source repository $source_repo is not a valid Git repository" >&2
        exit 1
    fi

    if [ ! -d "$target_repo/.git" ]; then
        echo "Error: Target repository $target_repo is not a valid Git repository" >&2
        exit 1
    fi

    # Update repositories
    echo "Updating repositories..."
    (cd "$source_repo" && git pull)
    (cd "$target_repo" && git pull)

    # Get all source commits
    echo "Analyzing commit history..."
    mapfile -t source_commits < <(get_repo_commits "$source_repo")

    processed=0
    skipped=0

    for source_commit in "${source_commits[@]}"; do
        # Skip if already synced
        if [ "$(is_commit_synced "$source_repo" "$source_commit")" -gt 0 ]; then
            echo "✓ Already synced: ${source_commit:0:7}"
            skipped=$((skipped + 1))
            continue
        fi

        echo "● Processing: ${source_commit:0:7}"
        
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
        if (cd "$target_repo" && git am --committer-date-is-author-date "$temp_dir/$source_commit.patch"); then
            # Get new commit hash
            target_commit=$(cd "$target_repo" && git rev-parse HEAD)
            
            # Record mapping
            record_commit_mapping \
                "$source_repo" "$target_repo" \
                "$source_commit" "$target_commit" \
                "$message" "$author" "$date"
            
            processed=$((processed + 1))
        else
            echo "Error applying patch for ${source_commit:0:7}" >&2
            (cd "$target_repo" && git am --abort)
            exit 1
        fi
    done

    # Clean up
    rm -rf "$temp_dir"

    echo ""
    echo "Sync complete:"
    echo "- Processed commits: $processed"
    echo "- Skipped commits: $skipped"
    echo ""
    echo "Commit mapping stored in: $db_file"
    echo "Don't forget to push the target repository if needed."
}

# Main Execution
# ------------------------------------------------------------------------------

init_db

# Validate base directories
if [ ! -d "$base_dir_source" ]; then
    echo "Error: Source base directory not found: $base_dir_source" >&2
    exit 1
fi

if [ ! -d "$base_dir_dest" ]; then
    echo "Error: Destination base directory not found: $base_dir_dest" >&2
    exit 1
fi

# Show repository list if no arguments
if [ "$#" -eq 0 ]; then
    list_available_repos
    exit 0
fi

# Start sync
sync_repository "$1" "$2"
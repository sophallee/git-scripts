#!/bin/bash

# Configuration
development_dir="$HOME/development/github"  # Path to development folder
excluded_repos=("app2" "app3")      # Repositories to exclude
log_file="/tmp/git_auto_pull.log"    # Log file path
debug=true                           # Enable verbose debugging

# ANSI colors
green='\033[0;32m'
yellow='\033[1;33m'
red='\033[0;31m'
nc='\033[0m' # No Color

# Initialize logging
echo -e "\nGit Auto Pull - $(date)\n" > "$log_file"

log() {
    local message="$1"
    local level="${2:-info}"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    case "$level" in
        "error") echo -e "${red}[$timestamp] ERROR: $message${nc}" | tee -a "$log_file" ;;
        "warn") echo -e "${yellow}[$timestamp] WARN: $message${nc}" | tee -a "$log_file" ;;
        "info") echo -e "${green}[$timestamp] INFO: $message${nc}" | tee -a "$log_file" ;;
        "debug") [ "$debug" = true ] && echo "[$timestamp] DEBUG: $message" | tee -a "$log_file" ;;
        *) echo -e "[$timestamp] $message" | tee -a "$log_file" ;;
    esac
}

check_for_updates() {
    local repo_dir="$1"
    cd "$repo_dir" || return 1
    
    # Refresh all remote tracking branches
    if ! git remote update > /dev/null 2>&1; then
        log "Failed to update remote references" "error"
        return 1
    fi

    # Get current branch
    local current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    [ -z "$current_branch" ] && return 1

    # Compare local and remote
    local local_ref=$(git rev-parse "$current_branch")
    local remote_ref=$(git rev-parse "origin/$current_branch")
    
    if [ "$local_ref" != "$remote_ref" ]; then
        log "Updates available (Local: ${local_ref:0:7} != Remote: ${remote_ref:0:7})" "debug"
        return 0
    fi
    
    log "No updates available" "debug"
    return 1
}

update_repo() {
    local repo_dir="$1"
    local repo_name=$(basename "$repo_dir")
    
    # Check exclusions
    for excluded in "${excluded_repos[@]}"; do
        [[ "$repo_name" == "$excluded" ]] && return 0
    done

    cd "$repo_dir" || {
        log "Cannot access $repo_name" "error"
        return 1
    }

    [ ! -d .git ] && {
        log "$repo_name is not a git repo" "warn"
        return 1
    }

    log "Checking $repo_name..." "info"
    
    if check_for_updates "$repo_dir"; then
        log "Pulling updates for $repo_name" "info"
        if git pull --ff-only 2>&1 | tee -a "$log_file"; then
            log "Successfully updated $repo_name" "info"
        else
            log "Pull failed for $repo_name" "error"
            return 1
        fi
    else
        log "$repo_name is up-to-date" "debug"
    fi
    
    return 0
}

# Main execution
log "Starting repository update check" "info"
log "Scanning directory: $development_dir" "debug"

for repo in "$development_dir"/*; do
    [ -d "$repo" ] && update_repo "$repo"
done

log "Update process completed" "info"
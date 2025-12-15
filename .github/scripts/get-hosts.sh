#!/usr/bin/env bash
set -e

# Change directory to the repository root (two levels up from .github/scripts)
cd "$(dirname "$0")/../../"

hosts=()

# Iterate over directories in vps/
for dir in vps/*/; do
    # Check if directory and contains flake.nix to be considered a valid host
    if [ -d "$dir" ] && [ -f "$dir/flake.nix" ]; then
        # Extract the directory name (host name)
        host=$(basename "$dir")
        hosts+=("$host")
    fi
done

# Output as JSON array using jq
if [ ${#hosts[@]} -eq 0 ]; then
    echo "[]"
else
    printf '%s\n' "${hosts[@]}" | jq -R . | jq -s -c .
fi

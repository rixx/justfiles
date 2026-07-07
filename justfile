set shell := ["bash", "-euo", "pipefail", "-c"]

home := home_directory()
justfiles := justfile_directory()
movesuffix := "moved-by-justfiles-install"

# Central mapping of justfiles to their target directories
# Format: "source.just:target_directory" (one per line)
mappings := "
ansible.just:" + home + "/src/ansible
c3queue.just:" + home + "/src/c3queue
clabot.just:" + home + "/src/clabot-config
djcrm.just:" + home + "/src/djcrm
dotfiles.just:" + home + "/.config/dotfiles
postix.just:" + home + "/src/postix
pretalx-docker.just:" + home + "/src/pretalx-docker
pretalx.just:" + home + "/src/pretalx
pretalx.just:" + home + "/tmp/pretalx
pretix-plugin.just:" + home + "/src/pretix/src/local/pretix-c3
pretix.just:" + home + "/src/pretix
schedule.just:" + home + "/src/schedule
servala.just:" + home + "/src/servala-portal
templates.just:" + home + "/doc/gewerbe/templates
tools.just:" + home + "/src/tools
"

[private]
default:
    @just --list

# Check status of all justfiles (installed, differs, missing)
[group('status')]
status:
    #!/usr/bin/env bash
    set -euo pipefail
    # Build associative array of mappings
    declare -A mapping_targets
    while IFS=: read -r source target; do
        [[ -z "$source" ]] && continue
        target="${target%/}"
        mapping_targets["$source"]="$target"
    done <<< '{{mappings}}'

    # Check all .just files
    for f in "{{justfiles}}"/*.just; do
        [[ -f "$f" ]] || continue
        source=$(basename "$f")
        target="${mapping_targets[$source]:-}"

        if [[ -z "$target" ]]; then
            echo "? $source: not in mappings"
        elif [[ ! -d "$target" ]]; then
            echo "⏭ $source -> $target (dir missing)"
        elif [[ ! -f "$target/justfile" ]]; then
            echo "✗ $source -> $target (not installed)"
        elif cmp -s "$f" "$target/justfile"; then
            echo "✓ $source -> $target"
        else
            echo "⚠ $source -> $target (differs)"
        fi
    done

# Copy a single justfile to a project directory
[private]
copy source target_dir:
    #!/usr/bin/env bash
    set -euo pipefail
    SOURCE="{{justfiles}}/{{source}}"
    TARGET_DIR="{{target_dir}}"
    TARGET_DIR="${TARGET_DIR%/}"  # Remove trailing slash if present
    TARGET="$TARGET_DIR/justfile"

    # Check if source exists
    if [[ ! -f "$SOURCE" ]]; then
        echo "Error: Source file {{source}} does not exist in repo"
        exit 1
    fi

    # Check if target directory exists
    if [[ ! -d "$TARGET_DIR" ]]; then
        echo "Info: $TARGET_DIR does not exist, skipping {{source}}"
        exit 0
    fi

    # Check if target already matches source
    if [[ -f "$TARGET" ]] && cmp -s "$SOURCE" "$TARGET"; then
        echo "OK: {{source}} already up to date"
        exit 0
    fi

    # Back up existing file if present
    if [[ -e "$TARGET" || -L "$TARGET" ]]; then
        echo "Moving existing $TARGET to $TARGET.{{movesuffix}}"
        mv "$TARGET" "$TARGET.{{movesuffix}}"
    fi

    # Copy file
    echo "Copying: {{source}} -> $TARGET"
    cp "$SOURCE" "$TARGET"

# Pull a single justfile from a project directory back to repo
[private]
pull-one source target_dir:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO="{{justfiles}}/{{source}}"
    TARGET_DIR="{{target_dir}}"
    TARGET_DIR="${TARGET_DIR%/}"
    INSTALLED="$TARGET_DIR/justfile"

    # Check if target directory exists
    if [[ ! -d "$TARGET_DIR" ]]; then
        exit 0
    fi

    # Check if installed file exists
    if [[ ! -f "$INSTALLED" ]]; then
        exit 0
    fi

    # Check if files already match
    if cmp -s "$REPO" "$INSTALLED"; then
        echo "OK: {{source}} already matches"
        exit 0
    fi

    # Copy installed file to repo
    echo "Pulling: $INSTALLED -> {{source}}"
    cp "$INSTALLED" "$REPO"

# Install all justfiles to their projects
[group('sync')]
install:
    #!/usr/bin/env bash
    set -euo pipefail
    while IFS=: read -r source target; do
        [[ -z "$source" ]] && continue
        just copy "$source" "$target"
    done <<< '{{mappings}}'

# Pull all modified justfiles from projects back to repo
[group('sync')]
pull:
    #!/usr/bin/env bash
    set -euo pipefail
    while IFS=: read -r source target; do
        [[ -z "$source" ]] && continue
        just pull-one "$source" "$target"
    done <<< '{{mappings}}'

# Show backup files that would be removed
[group('cleanup')]
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    found=()
    while IFS=: read -r source target; do
        [[ -z "$source" ]] && continue
        backup="$target/justfile.{{movesuffix}}"
        if [[ -f "$backup" ]]; then
            found+=("$backup")
        fi
    done <<< '{{mappings}}'

    if [[ ${#found[@]} -eq 0 ]]; then
        echo "No backup files found"
    else
        echo "Backup files (*.{{movesuffix}}):"
        for f in "${found[@]}"; do
            echo "  $f"
        done
        echo ""
        echo "Run 'just clean-confirm' to delete these files"
    fi

# Remove backup files created during install
[group('cleanup')]
clean-confirm:
    #!/usr/bin/env bash
    set -euo pipefail
    while IFS=: read -r source target; do
        [[ -z "$source" ]] && continue
        backup="$target/justfile.{{movesuffix}}"
        if [[ -f "$backup" ]]; then
            rm "$backup"
            echo "Removed: $backup"
        fi
    done <<< '{{mappings}}'

# Show differences between repo and installed justfiles
[group('status')]
diff:
    #!/usr/bin/env bash
    set -euo pipefail
    while IFS=: read -r source target; do
        [[ -z "$source" ]] && continue
        target="${target%/}"
        installed="$target/justfile"
        repo="{{justfiles}}/$source"

        [[ ! -d "$target" ]] && continue
        [[ ! -f "$installed" ]] && continue

        if ! cmp -s "$repo" "$installed"; then
            echo "=== $source ($installed) ==="
            diff -u "$installed" "$repo" || true
            echo ""
        fi
    done <<< '{{mappings}}'

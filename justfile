set shell := ["bash", "-euo", "pipefail", "-c"]
set fallback := true

home := home_directory()
justfiles := justfile_directory()
movesuffix := "moved-by-justfiles-install"

# Local override of root.just's `strings`: this repo defines the marker tooling,
# so root.just and this justfile legitimately contain the ⁂ glyph in code and
# messages. Exclude both so the loop doesn't trap on its own machinery.
marker_grep := "grep -rIn --exclude=root.just --exclude=justfile --exclude-dir={.git,.venv,node_modules,dist,build,_build,data,htmlcov,static.dist} '⁂' . | grep -v '[⸻❧꧁꧂☙]'"

# Central mapping of justfiles to their target directories
# Format: "source.just:target_directory" (one per line)
mappings := "
root.just:" + home + "
ansible.just:" + home + "/src/ansible
c3queue.just:" + home + "/src/c3queue
clabot.just:" + home + "/src/clabot-config
djcrm.just:" + home + "/src/djcrm
dotfiles.just:" + home + "/.config/dotfiles
postix.just:" + home + "/src/postix
pretalx-docker.just:" + home + "/src/pretalx-docker
pretalx.just:" + home + "/src/pretalx
pretalx.just:" + home + "/tmp/pretalx
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-com
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-downstream
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-friendlycaptcha
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-fontpack-free
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-media-ccc-de
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-pages
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-public-voting
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-salesforce
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-venueless
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-vimeo
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-youtube
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-broadcast-tools
pretalx-plugin.just:" + home + "/src/pretalx/main/src/local/pretalx-plugin-cookiecutter/{{cookiecutter.__repo_name}}
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
    # Check each source -> target mapping (a source may map to several targets)
    declare -A seen_sources
    while IFS=: read -r source target; do
        [[ -z "$source" ]] && continue
        target="${target%/}"
        seen_sources["$source"]=1
        repo="{{justfiles}}/$source"
        installed="$target/justfile"

        if [[ ! -f "$repo" ]]; then
            echo "? $source -> $target (source missing)"
        elif [[ ! -d "$target" ]]; then
            echo "⏭ $source -> $target (dir missing)"
        elif [[ ! -f "$installed" ]]; then
            echo "✗ $source -> $target (not installed)"
        elif cmp -s "$repo" "$installed"; then
            echo "✓ $source -> $target"
        else
            echo "⚠ $source -> $target (differs)"
        fi
    done <<< '{{mappings}}'

    # Report .just files not referenced by any mapping
    for f in "{{justfiles}}"/*.just; do
        [[ -f "$f" ]] || continue
        source=$(basename "$f")
        [[ -n "${seen_sources[$source]:-}" ]] && continue
        echo "? $source: not in mappings"
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

# Resolve string markers
strings:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="${INVOCATION_DIRECTORY:-$(readlink "/proc/$PPID/cwd" 2>/dev/null || true)}"
    cd "${dir:-$PWD}"
    found=
    while hit=$({{ marker_grep }} | head -n1); [ -n "$hit" ]; do
        found=1
        file=${hit%%:*}
        rest=${hit#*:}
        ${EDITOR:-nvim} "+${rest%%:*}" -c "let @/='⁂'" -c "set hlsearch" "$file"
    done
    if [ -n "$found" ]; then
        if just --summary 2>/dev/null | tr ' ' '\n' | grep -qx fmt; then
            just fmt 2>/dev/null || true
        fi
    else
        echo "No ⁂ string markers found."
    fi

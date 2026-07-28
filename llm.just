set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

home := home_directory()
repo := justfile_directory()
movesuffix := "moved-by-llm-install"

# Local override of root.just's `strings`: this repo stores the prompts that
# define the marker convention, so claude-md/root.md and prompts/string-markers.md
# legitimately contain the ⁂ glyph. Exclude both so the loop doesn't trap on them.
marker_grep := "grep -rIn --exclude=justfile --exclude=root.md --exclude=string-markers.md --exclude-dir={.git,.venv,node_modules,dist,build,_build,data,htmlcov,static.dist} '⁂' . | grep -v '[⸻❧꧁꧂☙]'"

# Central mapping of repo files to the places the tools expect them.
# Format: "repo/path:/absolute/target/path" (one per line). Sources may be
# files or directories.
mappings := "
claude-md/root.md:" + home + "/CLAUDE.md
claude-md/pretalx.md:" + home + "/src/pretalx/main/CLAUDE.md
skills/pretalx-changelog:" + home + "/src/pretalx/main/.claude/skills/pretalx-changelog
skills/compress-tests:" + home + "/src/pretalx/main/.claude/skills/compress-tests
skills/pxtx-dev:" + home + "/src/pretalx/main/.claude/skills/pxtx-dev
skills/pretalx-translations:" + home + "/src/pretalx/main/.claude/skills/pretalx-translations
skills/release-blog-post:" + home + "/src/pretalx/main/.claude/skills/release-blog-post
skills/visual-check:" + home + "/src/pretalx/main/.claude/skills/visual-check
hooks/check-uv-pytest.py:" + home + "/src/pretalx/main/.claude/hooks/check-uv-pytest.py
skills/github-notif-triage:" + home + "/.claude/skills/github-notif-triage
skills/multi-review:" + home + "/.claude/skills/multi-review
hooks/head-tail.py:" + home + "/.claude/hooks/head-tail.py
"

# Helper shared by the recipes below (sourced via eval)
mapping_lib := '''
each_mapping() {
    local callback="$1" source target
    while IFS=: read -r source target; do
        [[ -z "$source" ]] && continue
        "$callback" "$source" "${target%/}"
    done <<< "$MAPPINGS"
}
'''

# Check which mappings are linked, missing, or hijacked
[group('status')]
[script('bash')]
status:
    set -euo pipefail
    REPO="{{ repo }}"
    MAPPINGS='{{ mappings }}'
    eval '{{ mapping_lib }}'

    problems=()
    check() {
        local source="$1" target="$2"
        local origin="$REPO/$source"

        if [[ ! -e "$origin" ]]; then
            problems+=("? $source -> $target (source missing)")
        elif [[ ! -d "$(dirname "$target")" ]]; then
            : # Target lives in a project that is not checked out here
        elif [[ -L "$target" ]]; then
            local actual
            actual="$(readlink -f "$target" || true)"
            if [[ "$actual" != "$(readlink -f "$origin")" ]]; then
                problems+=("⚠ $source -> $target (links to $actual)")
            fi
        elif [[ -e "$target" ]]; then
            problems+=("⚠ $source -> $target (exists, not a symlink)")
        else
            problems+=("✗ $source -> $target (not linked)")
        fi
    }
    each_mapping check

    if [[ ${#problems[@]} -eq 0 ]]; then
        echo "All files linked."
    else
        printf '%s\n' "${problems[@]}"
    fi

# Link a single repo file to its target path
[private]
[script('bash')]
link-one source target:
    set -euo pipefail
    ORIGIN="{{ repo }}/{{ source }}"
    TARGET="{{ target }}"

    # Warn rather than fail: one stale mapping should not stop the rest
    if [[ ! -e "$ORIGIN" ]]; then
        echo "Skipping {{ source }}: it does not exist in the repo"
        exit 0
    fi

    # Missing parent means the project is not checked out on this machine
    if [[ ! -d "$(dirname "$TARGET")" ]]; then
        exit 0
    fi

    if [[ -L "$TARGET" && "$(readlink -f "$TARGET" || true)" == "$(readlink -f "$ORIGIN")" ]]; then
        exit 0
    fi

    if [[ -e "$TARGET" || -L "$TARGET" ]]; then
        echo "Moving existing $TARGET to $TARGET.{{ movesuffix }}"
        mv "$TARGET" "$TARGET.{{ movesuffix }}"
    fi

    echo "Linking: {{ source }} -> $TARGET"
    ln -s "$ORIGIN" "$TARGET"

# Link every mapped file into place
[group('sync')]
[script('bash')]
install:
    set -euo pipefail
    MAPPINGS='{{ mappings }}'
    eval '{{ mapping_lib }}'

    install_one() { just link-one "$1" "$2"; }
    each_mapping install_one

# Replace our symlinks with real copies, e.g. before handing a machine over
[group('sync')]
[script('bash')]
unlink:
    set -euo pipefail
    REPO="{{ repo }}"
    MAPPINGS='{{ mappings }}'
    eval '{{ mapping_lib }}'

    detach() {
        local source="$1" target="$2"
        local origin="$REPO/$source"
        [[ -L "$target" ]] || return 0
        [[ "$(readlink -f "$target" || true)" == "$(readlink -f "$origin")" ]] || return 0
        rm "$target"
        cp -r "$origin" "$target"
        echo "Detached: $target"
    }
    each_mapping detach

# Move an existing file into the repo and link it back (target first, then repo path)
[group('sync')]
[script('bash')]
adopt target source:
    set -euo pipefail
    TARGET="{{ target }}"
    ORIGIN="{{ repo }}/{{ source }}"

    if [[ ! -e "$TARGET" ]]; then
        echo "Error: $TARGET does not exist"
        exit 1
    fi
    if [[ -L "$TARGET" ]]; then
        echo "Error: $TARGET is already a symlink"
        exit 1
    fi
    if [[ -e "$ORIGIN" ]]; then
        echo "Error: {{ source }} already exists in the repo"
        exit 1
    fi

    mkdir -p "$(dirname "$ORIGIN")"
    mv "$TARGET" "$ORIGIN"
    ln -s "$ORIGIN" "$TARGET"
    echo "Adopted: $TARGET -> {{ source }}"
    echo ""
    echo "Add this line to the mappings:"
    echo "{{ source }}:$TARGET"

# Show backup files that would be removed
[group('cleanup')]
[script('bash')]
clean:
    set -euo pipefail
    MAPPINGS='{{ mappings }}'
    eval '{{ mapping_lib }}'

    found=()
    collect() {
        local backup="$2.{{ movesuffix }}"
        if [[ -e "$backup" ]]; then
            found+=("$backup")
        fi
    }
    each_mapping collect

    if [[ ${#found[@]} -eq 0 ]]; then
        echo "No backup files found."
    else
        echo "Backup files (*.{{ movesuffix }}):"
        printf '  %s\n' "${found[@]}"
        echo ""
        echo "Run 'just clean-confirm' to delete these files."
    fi

# Remove backup files created while linking
[group('cleanup')]
[script('bash')]
clean-confirm:
    set -euo pipefail
    MAPPINGS='{{ mappings }}'
    eval '{{ mapping_lib }}'

    remove() {
        local backup="$2.{{ movesuffix }}"
        if [[ -e "$backup" ]]; then
            rm -r "$backup"
            echo "Removed: $backup"
        fi
    }
    each_mapping remove

# Resolve string markers
[script('bash')]
strings:
    set -euo pipefail
    # Under `set fallback`, just clears INVOCATION_DIRECTORY and runs us from the
    # parent justfile's dir; the parent `just` process ($PPID) keeps the real cwd.
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
        # Reformat if this project defines a `fmt` recipe, but never let a missing
        # recipe or a formatting error fail the strings run.
        if just --summary 2>/dev/null | tr ' ' '\n' | grep -qx fmt; then
            echo "Running fmt …"
            just fmt 2>/dev/null || true
        fi
    else
        echo "No ⁂ string markers found."
    fi

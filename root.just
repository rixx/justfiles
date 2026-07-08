set quiet
set default-list

# Exclude lines where the AI text marker appears among decorative glyphs (e.g. sway/waybar title ornaments)
# rather than as an AI-authored-text marker.
marker_grep := "grep -rIn --exclude=justfile --exclude-dir={.git,.venv,node_modules,dist,build,_build,data,htmlcov,static.dist} '⁂' . | grep -v '[⸻❧꧁꧂☙]'"

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
            just fmt 2>/dev/null || true
        fi
    else
        echo "No ⁂ string markers found."
    fi

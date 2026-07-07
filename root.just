set quiet

[private]
default:
    just --list

marker_grep := "grep -rIn --exclude-dir={.git,.venv,node_modules,dist,build,_build,data,htmlcov,static.dist} '⁂' src doc"

strings:
    #!/usr/bin/env bash
    set -euo pipefail
    # ⁂ Under `set fallback`, just clears INVOCATION_DIRECTORY and runs us from the
    # ⁂ parent justfile's dir; the parent `just` process ($PPID) keeps the real cwd.
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
        just fmt
    else
        echo "No ⁂ string markers found."
    fi


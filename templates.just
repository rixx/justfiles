set shell := ["bash", "-euo", "pipefail", "-c"]
set fallback := true

[private]
default:
    @just --list

# Build a PDF from a LaTeX file and clean up auxiliary files
# Runs lualatex twice to resolve references (page numbers, etc.)
build file:
    #!/usr/bin/env bash
    cd "{{parent_directory(file)}}"
    lualatex "{{file_name(file)}}"
    lualatex "{{file_name(file)}}"
    base="{{file_stem(file)}}"
    rm -f "$base".aux "$base".log "$base".out "$base".toc "$base".lof "$base".lot "$base".fls "$base".fdb_latexmk "$base".synctex.gz

# Copy compiled documents to pretalx and legal repositories
publish:
    cp cla/* ../legal/cla/
    cp auftragsdatenverarbeitung/*.pdf ~/src/pretalx/src/local/pretalx-com/pretalx_com/static/pretalx_com/terms/
    cp cla/cla.pdf ~/src/pretalx/src/local/pretalx-com/pretalx_com/static/pretalx_com/terms/
    cp terms-of-service/*.pdf ~/src/pretalx/src/local/pretalx-com/pretalx_com/static/pretalx_com/terms/
    cp terms-of-service/* ../legal/terms-of-service
    cp pretalx.cls ../legal

# Remove LaTeX build artifacts from all subdirectories
clean:
    find . -type f \( -name "*.aux" -o -name "*.log" -o -name "*.out" -o -name "*.toc" -o -name "*.lof" -o -name "*.lot" -o -name "*.fls" -o -name "*.fdb_latexmk" -o -name "*.synctex.gz" -o -name "*.bbl" -o -name "*.blg" -o -name "*.nav" -o -name "*.snm" -o -name "*.vrb" \) -delete

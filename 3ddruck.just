set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Print settings of a PrusaSlicer 3mf as one line for a printables make; -v for one per line
info file *args:
    python3 scripts/printsettings.py {{ args }} "{{ file }}"

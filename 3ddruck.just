set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Print settings of a PrusaSlicer 3mf as one line for a printables make; -v for one per line
info file *args:
    python3 scripts/printsettings.py {{ args }} "{{ file }}"

# Show a PrusaSlicer print preset key across user presets: just preset-get fill_pattern ["0.20*"]
[group('presets')]
[positional-arguments]
preset-get key glob="*":
    python3 scripts/presets.py get "$@"

# Set a key in every matching user print preset (backup under ~/.local/state/prusaslicer-presets): just preset-set seam_position rear ["0.1*"]
[group('presets')]
[positional-arguments]
preset-set key value glob="*":
    python3 scripts/presets.py set "$@"

# Slice an STL with resolved presets, print time and filament: just slice part.stl "0.28*" [-f "Prusament PLA Blend @COREONE"] [-s key=value]
[group('presets')]
[positional-arguments]
slice stl preset *args:
    python3 scripts/presets.py slice "$@"

# Show what user print presets change against their system parents; -a includes keys the bundle does not set
[group('presets')]
[positional-arguments]
preset-diff *args:
    python3 scripts/presets.py diff "$@"

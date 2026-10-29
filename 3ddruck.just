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

# Set a key in every matching user print preset: just preset-set seam_position rear ["0.1*"]
[group('presets')]
[positional-arguments]
preset-set key value glob="*":
    python3 scripts/presets.py set "$@"

# Create a user preset from a system parent with the full key set: just preset-new filament "Name" "Generic PLA @COREONE HF0.4" [-s key=value]
[group('presets')]
[positional-arguments]
preset-new kind name parent *args:
    python3 scripts/presets.py --kind "$1" new "${@:2}"

# Slice an STL with resolved presets, print time and filament: just slice part.stl "0.28*" [-f "Prusament PLA Blend @COREONE"] [-s key=value]
[group('presets')]
[positional-arguments]
slice stl preset *args:
    python3 scripts/presets.py slice "$@"

# Predict torn wall bands and recommend settings: just settings-rec part.3mf [--max-slices 12] slices and searches seam/perimeter settings; part.gcode [--png] [--out DIR] gives the verdict only
[no-cd]
[positional-arguments]
settings-rec file *args:
    uv run --with heatshrink2 --with numpy --with scipy --with matplotlib python3 "{{ justfile_directory() }}/scripts/settings_rec.py" "$@"

# Show what user print presets change against their system parents; -a includes keys the bundle does not set
[group('presets')]
[positional-arguments]
preset-diff *args:
    python3 scripts/presets.py diff "$@"

# Label a filament swatch, asks interactively without arguments: just swatch [TYPE MAKER COLOUR --temp 255/85 …]
[positional-arguments]
swatch *args:
    if [ $# -eq 0 ]; then scripts/swatch.py --interactive; else scripts/swatch.py "$@"; fi

# Generate, slice and verify a calibration print, see calibration/README.md: just calibrate temp|mvs|pa|em [-f FILAMENT] [-p "0.20mm structural"] [--values 245,240,...]
[group('presets')]
[positional-arguments]
calibrate test *args:
    python3 scripts/calibrate.py "$@"

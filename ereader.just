set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Show connected devices
[group('device')]
devices:
    adb devices

# Unlock the vendor adbd (persistent); `just adb-unlock off` re-locks
[group('device')]
adb-unlock *args:
    ./viwoods-reader/adb-unlock.sh {{ args }}

# Disable vendor bloat via pm; `just debloat --undo` re-enables
[group('device')]
debloat *args:
    ./viwoods-reader/debloat.sh {{ args }}

# Write the AI-key keymap (tap corner, wait, lock) into Key Mapper's database
[group('device')]
keymap:
    ./viwoods-reader/keymapper/write-keymap.sh

# Build NoStripe.apk (fetches build-tools and framework-res on first run)
[group('nostripe')]
nostripe-build:
    ./viwoods-reader/nostripe/build.sh

# Apply, check or remove the sleep-screen bar overlay: apply | check | remove (exit 1 = not active)
[group('nostripe')]
nostripe mode="apply":
    ./viwoods-reader/nostripe/apply.sh {{ mode }}

# Pull tracked KOReader config from the device into koreader/config (refuses on uncommitted changes, --force)
[group('koreader')]
pull *args:
    ./koreader/sync.sh pull {{ args }}

# Push koreader/config and patches to the device (needs --yes)
[group('koreader')]
push *args:
    ./koreader/sync.sh push {{ args }}

# Diff device config against koreader/config (exit 1 = differs)
[group('koreader')]
diff *args:
    ./koreader/sync.sh diff {{ args }}

# Run the screensaver picker web UI (migrates first); extra args go to runserver
[group('screensavers')]
pick *args:
    cd koreader/screensavers/picker && uv run manage.py migrate -v0 && uv run manage.py runserver {{ args }}

# Fetch catalog metadata for the picker (decisions are kept)
[group('screensavers')]
pick-refresh *args:
    cd koreader/screensavers/picker && uv run manage.py refresh {{ args }}

# Add hand-picked images (files or URLs) to triage; `--tag NAME` repeatable
[group('screensavers')]
[positional-arguments]
pick-add *args:
    cd koreader/screensavers/picker && uv run manage.py add --cwd "{{ invocation_directory() }}" "$@"

# Download untriaged originals in queue order plus thumbnails for the rest; `--limit N`
[group('screensavers')]
pick-fetch *args:
    cd koreader/screensavers/picker && uv run manage.py fetch {{ args }}

# Mirror screensavers/out to the device; `--dry-run` to preview
[group('screensavers')]
sync *args:
    cd koreader/screensavers/picker && uv run manage.py sync {{ args }}

# Triage counts, out/ consistency and device state
[group('screensavers')]
status *args:
    cd koreader/screensavers/picker && uv run manage.py status {{ args }}

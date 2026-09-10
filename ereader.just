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

# Rebuild the screensaver placement picker; `--open` opens it in the browser
[group('screensavers')]
pick *args:
    ./koreader/screensavers/manage.py pick {{ args }}

# Render plan.txt into screensavers/out
[group('screensavers')]
apply *args:
    ./koreader/screensavers/manage.py apply {{ args }}

# Mirror screensavers/out to the device, then trash delete-only originals; `--dry-run` to preview
[group('screensavers')]
sync *args:
    ./koreader/screensavers/manage.py sync {{ args }}

# Trash originals whose plan lines are all `delete` and drop them from plan.txt
[group('screensavers')]
prune *args:
    ./koreader/screensavers/manage.py prune {{ args }}

# Compare originals, plan, out and device
[group('screensavers')]
status *args:
    ./koreader/screensavers/manage.py status {{ args }}

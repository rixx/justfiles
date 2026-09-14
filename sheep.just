set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Build the debug binary
[group('build')]
build:
    cargo build

# Build the optimized release binary
[group('build')]
release:
    cargo build --release

# Remove build artifacts
[group('build')]
clean:
    cargo clean

# Run the debug binary; args go to sheep as is, e.g. `just run --count 2 --scale 2`
[group('development')]
run *args:
    cargo run -- {{ args }}

# Run the test suite
[group('development')]
test *args:
    cargo test {{ args }}

# Build and open the API docs
[group('development')]
doc:
    cargo doc --no-deps --open

# Run the windows example, showing what the sway backend sees
[group('development')]
windows:
    cargo run --example windows

# Format code and auto-fix lint issues
[group('quality')]
fmt:
    cargo fmt
    cargo clippy --all-targets --fix --allow-dirty --allow-staged

# Check formatting, lints, and tests without changing anything
[group('quality')]
check:
    cargo fmt --check
    cargo clippy --all-targets -- -D warnings
    cargo test

# Install the sheep binary, icon, and desktop entry
[group('install')]
install:
    cargo install --path . --locked --root ~/.local
    mkdir -p ~/.local/share/icons/hicolor/256x256/apps ~/.local/share/icons/hicolor/64x64/apps ~/.local/share/applications
    cp assets/icon.png ~/.local/share/icons/hicolor/256x256/apps/sheep.png
    cp assets/icon-64.png ~/.local/share/icons/hicolor/64x64/apps/sheep.png
    cp assets/sheep.desktop ~/.local/share/applications/sheep.desktop
    command -v update-desktop-database >/dev/null && update-desktop-database ~/.local/share/applications || true

# Remove the sheep binary, icon, and desktop entry
[group('install')]
uninstall:
    rm -f ~/.local/bin/sheep
    rm -f ~/.local/share/icons/hicolor/256x256/apps/sheep.png
    rm -f ~/.local/share/icons/hicolor/64x64/apps/sheep.png
    rm -f ~/.local/share/applications/sheep.desktop
    command -v update-desktop-database >/dev/null && update-desktop-database ~/.local/share/applications || true

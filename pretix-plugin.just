set shell := ["bash", "-euo", "pipefail", "-c"]
set fallback := true

# Check for required tools
_ := require("uvx")

export BIN := "../../.venv/bin"

[private]
default:
    @just --list

# Run all code quality checks (black, isort, flake8)
[group('linting')]
check:
    uvx black --check pretix_scheduling/
    uvx isort --check --gitignore pretix_scheduling/
    uvx flake8 --extend-exclude .cache pretix_scheduling/
    @echo '{{ GREEN }}All checks passed{{ NORMAL }}'

# Run all formatters (black, isort)
[group('linting')]
fmt:
    uvx black pretix_scheduling/
    uvx isort --gitignore pretix_scheduling/
    @echo '{{ GREEN }}Formatting complete{{ NORMAL }}'

# Run a command from the venv bin directory (defaults to python)
[group('development')]
run *args="python":
    $BIN/{{ args }}

# Run test suite (runs with coverage if no args given)
[group('tests')]
test *args="":
    #!/usr/bin/env bash
    if [[ -n "{{ args }}" ]]; then
        $BIN/pytest {{ args }}
    else
        $BIN/coverage run --module pytest
        $BIN/coverage report
        $BIN/coverage html
    fi

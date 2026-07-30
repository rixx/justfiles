# SPDX-FileCopyrightText: 2025-present Tobias Kunze
# SPDX-License-Identifier: Apache-2.0

set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Common variables
python := "uv run python"

# Install dependencies (use --extras to include e.g. dev, devdocs, postgres, redis)
[group('development')]
install *args:
    uv pip install -r src/requirements.txt {{ args }}

# Run the development server or other commands, e.g. `just run makemigrations`
[group('development')]
[working-directory("src")]
[positional-arguments]
run *args:
    @if [ "$#" -eq 0 ]; then set -- runserver --skip-checks; fi; {{ python }} manage.py "$@"

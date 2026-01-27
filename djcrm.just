# SPDX-FileCopyrightText: 2025-present Tobias Kunze
# SPDX-License-Identifier: Apache-2.0

# Common variables
python := "uv run python"

default:
    @just --list

# Install dependencies (use --extras to include e.g. dev, devdocs, postgres, redis)
[group('development')]
install *args:
    uv pip install -r src/requirements.txt {{ args }}

# Run the development server or other commands, e.g. `just run makemigrations`
[group('development')]
[working-directory("src")]
run *args="runserver --skip-checks":
    {{ python }} manage.py {{ args }}

# Update translation files
[group('development')]
[working-directory("src")]
makemessages:
    just run collectstatic --npm-install
    just run makemessages --keep-pot --all

# Build the documentation
[group('documentation')]
[working-directory("doc")]
docs *args="html":
    uv run make {{ args }}

# Serve the documentation from a live server
[group('documentation')]
[working-directory("doc")]
serve-docs *args="--port 8001":
    uv run sphinx-autobuild . _build/html {{ args }}

# Update the API documentation
[group('documentation')]
api-docs:
    just run spectacular --color --file ../doc/api/schema.yml

# Check codebase for licensing problems
[group('linting')]
[working-directory("src")]
reuse:
    uv run reuse lint

# Format code with black
[group('linting')]
[working-directory("src")]
black *args=".":
    uv run black {{ args }}

# Check code with black (check only)
[group('linting')]
black-check *args=".":
    just black --check {{ args }}

# Check import sorting with isort (check only)
[group('linting')]
isort-check *args=".":
    just isort --check {{ args }}

# Sort imports with isort
[group('linting')]
[working-directory("src")]
isort *args=".":
    uv run isort {{ args }}

# Run flake8 linter
[group('linting')]
[working-directory("src")]
flake8 *args=".":
    uv run flake8 {{ args }}

# Check Django templates with djhtml (check only)
[group('linting')]
djhtml-check:
    just djhtml --check

# Format Django templates with djhtml
[group('linting')]
[working-directory("src")]
djhtml *args:
    find . -name "*.html" -not -path '*/vendored/*' -not -path '*/node_modules/*' -not -path '*/htmlcov/*' -not -path '*/local/*' -not -path '*dist/*' -not -path "*.min.html" -not -path '*/pretalx-schedule' -print | xargs uv run djhtml {{ args }}

# Run all formatters and linters
[group('linting')]
[parallel]
fmt: black isort djhtml flake8

# Run all code quality checks
[group('linting')]
[parallel]
check: black-check isort-check djhtml-check flake8

# Open Django shell with access to all events
[group('development')]
[working-directory("src")]
[no-exit-message]
shell event="" *args:
    just run shell --event {{ event }} {{ args }}

# Open Django shell with access to all events
[group('development')]
[working-directory("src")]
[no-exit-message]
unsafe-shell *args:
    just run shell --unsafe-disable-scopes {{ args }}

# Clean up generated files
[group('development')]
clean:
    find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
    find . -type f -name "*.pyc" -delete
    find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    rm -rf .pytest_cache
    rm -rf .coverage htmlcov
    rm -rf dist build

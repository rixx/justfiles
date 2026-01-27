set dotenv-load := true

[private]
default:
    @just --list

# Install dependencies (use --extras to include e.g. dev)
[group('development')]
install *args:
    uv lock --upgrade
    uv sync {{ args }}

# Install all dependencies (dev)
[group('development')]
install-all:
    uv lock --upgrade
    uv sync --all-extras

# Run the development server or other commands, e.g. `just run makemigrations`
[group('development')]
[working-directory("src")]
run *args="runserver --skip-checks":
    uv run python manage.py {{ args }}

# Update translation files
[group('development')]
[working-directory("src")]
makemessages:
    just run makemessages --keep-pot --all

# Open Django shell with access to all events
[group('development')]
shell *args:
    just run shell

# Format code with black
[group('linting')]
black *args="src":
    uv run --extra=dev black {{ args }}

# Check code with black (check only)
[group('linting')]
black-check *args="src":
    just black --check {{ args }}

# Check import sorting with isort (check only)
[group('linting')]
isort-check *args="src":
    just isort --check {{ args }}

# Sort imports with isort
[group('linting')]
isort *args="src":
    uv run --extra=dev isort {{ args }}

# Run flake8 linter
[group('linting')]
flake8 *args="src":
    uv run --extra=dev flake8 {{ args }}

# Check Django templates with djhtml (check only)
[group('linting')]
djhtml-check:
    just djhtml --check

# Format Django templates with djhtml
[group('linting')]
djhtml *args="":
    find src/ -name "*.html" -not -path '*/vendored/*' -not -path '*/node_modules/*' -not -path '*/htmlcov/*' -not -path '*/local/*' -not -path '*dist/*' -not -path "*.min.html" -print | xargs uv run --extra=dev djhtml {{ args }}

# Run all formatters and linters
[group('linting')]
fmt: black isort djhtml flake8

# Run all code quality checks
[group('linting')]
check: black-check isort-check djhtml-check flake8

# List outdated dependencies
[group('development')]
deps-outdated:
    uv pip list --outdated --format=json | python -c "\
    import json, sys, tomllib; \
    from packaging.requirements import Requirement; \
    outdated = {p['name'].lower(): p for p in json.load(sys.stdin)}; \
    deps = tomllib.load(open('pyproject.toml', 'rb')).get('project', {}).get('dependencies', []); \
    direct = {Requirement(d).name.lower() for d in deps}; \
    [print(f\"{p['name']}: {p['version']} → {p['latest_version']}\") for name in sorted(outdated.keys() & direct) if (p := outdated[name])]"

# Bump a dependency version
[group('development')]
deps-bump package version:
    python -c "\
    import tomllib; \
    from pathlib import Path; \
    from packaging.requirements import Requirement; \
    p = Path('pyproject.toml'); \
    deps = tomllib.load(open('pyproject.toml', 'rb')).get('project', {}).get('dependencies', []); \
    old = next((d for d in deps if Requirement(d).name.lower() == '{{package}}'.lower()), None); \
    old and p.write_text(p.read_text().replace(old, f'{Requirement(old).name}~={{version}}'))"
    uv lock --upgrade-package {{package}}

# Clean up generated files
[group('development')]
clean:
    find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
    find . -type f -name "*.pyc" -delete
    find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    rm -rf .pytest_cache
    rm -rf .coverage htmlcov
    rm -rf dist build

# Run the test suite
[group('tests')]
test *args:
    uv run --extra=dev pytest {{ args }}

# Run tests in parallel (requires pytest-xdist)
[group('tests')]
[working-directory("src")]
test-parallel n="auto" *args:
    just test -n {{ n }} {{ args }}

# Show test coverage report in browser
[group('tests')]
[working-directory("src")]
test-coverage-report: test
    open htmlcov/index.html || xdg-open htmlcov/index.html || echo "Coverage report generated in htmlcov/index.html"

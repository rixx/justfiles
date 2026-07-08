set dotenv-load
set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Common variables
python := "uv run --frozen python"
uv_dev := "uv run --frozen --extra=dev"
src_dir := "src"

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
    {{ python }} manage.py {{ args }}

# Update translation files
[group('development')]
[working-directory("src")]
makemessages:
    just run makemessages --keep-pot --all

# Open Django shell
[group('development')]
[no-exit-message]
shell *args:
    just run shell

# Format code with black
[group('linting')]
black *args=src_dir:
    {{ uv_dev }} black {{ args }}

# Check code with black (check only)
[group('linting')]
black-check *args=src_dir:
    just black --check {{ args }}

# Check import sorting with isort (check only)
[group('linting')]
isort-check *args=src_dir:
    just isort --check {{ args }}

# Sort imports with isort
[group('linting')]
isort *args=src_dir:
    {{ uv_dev }} isort {{ args }}

# Run flake8 linter
[group('linting')]
flake8 *args=src_dir:
    {{ uv_dev }} flake8 {{ args }}

# Check Django templates with djhtml (check only)
[group('linting')]
djhtml-check:
    just djhtml --check

# Format Django templates with djhtml
[group('linting')]
djhtml *args="":
    find src/ -name "*.html" -not -path '*/vendored/*' -not -path '*/node_modules/*' -not -path '*/htmlcov/*' -not -path '*/local/*' -not -path '*dist/*' -not -path "*.min.html" -print | xargs {{ uv_dev }} djhtml {{ args }}

# Run all formatters and linters
[group('linting')]
[parallel]
fmt: black isort djhtml flake8 && fmt-done

[private]
fmt-done:
    echo '{{ GREEN }}Formatting complete{{ NORMAL }}'

# Run all code quality checks
[group('linting')]
[parallel]
check: black-check isort-check djhtml-check flake8 && check-done

[private]
check-done:
    echo '{{ GREEN }}All checks passed{{ NORMAL }}'

# Check for outdated dependencies
[group('development')]
[script('python3')]
deps-outdated:
    import json, subprocess, tomllib
    from packaging.requirements import Requirement

    result = subprocess.run(['uv', 'pip', 'list', '--outdated', '--format=json'], capture_output=True, text=True)
    outdated = {p['name'].lower(): p for p in json.loads(result.stdout)}
    deps = tomllib.load(open('pyproject.toml', 'rb')).get('project', {}).get('dependencies', [])
    direct = {Requirement(d).name.lower() for d in deps}

    for name in sorted(outdated.keys() & direct):
        p = outdated[name]
        print(f"{p['name']}: {p['version']} → {p['latest_version']}")

# Bump a dependency version
[group('development')]
[script('python3')]
deps-bump package version:
    import subprocess, tomllib
    from pathlib import Path
    from packaging.requirements import Requirement

    p = Path('pyproject.toml')
    deps = tomllib.load(open('pyproject.toml', 'rb')).get('project', {}).get('dependencies', [])
    old = next((d for d in deps if Requirement(d).name.lower() == '{{ package }}'.lower()), None)
    if old:
        p.write_text(p.read_text().replace(old, f'{Requirement(old).name}~={{ version }}'))
    subprocess.run(['uv', 'lock', '--upgrade-package', '{{ package }}'])

# Remove Python caches, build artifacts, and coverage reports
[group('development')]
clean:
    -find . -type d -name __pycache__ -exec rm -rf {} +
    -find . -type f -name "*.pyc" -delete
    -find . -type d -name "*.egg-info" -exec rm -rf {} +
    -rm -rf .pytest_cache .coverage htmlcov dist build

# Run the test suite
[group('tests')]
test *args:
    {{ uv_dev }} pytest {{ args }}

# Run tests in parallel (requires pytest-xdist)
[group('tests')]
[working-directory("src")]
test-parallel n="auto" *args:
    just test -n {{ n }} {{ args }}

# Show test coverage report in browser
[group('tests')]
[script('sh')]
test-coverage-report: test
    if [ -f "src/htmlcov/index.html" ]; then
        open src/htmlcov/index.html 2>/dev/null || \
        xdg-open src/htmlcov/index.html 2>/dev/null || \
        echo "Coverage report: src/htmlcov/index.html"
    else
        echo "No coverage report found. Run just test first."
    fi

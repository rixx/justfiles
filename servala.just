set dotenv-load
set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Install dependencies for production
[group('development')]
install *args:
    uv sync {{ args }}

# Install all dependencies (including development dependencies)
[group('development')]
install-all:
    uv sync --all-extras

# Run the development server or other commands, e.g. `just run makemigrations`
[group('development')]
[script('bash')]
[working-directory("src")]
run *args="runserver --skip-checks":
    uv run python manage.py {{ args }}

[group('development')]
[no-exit-message]
[positional-arguments]
[working-directory("src")]
python *args:
    uv run python manage.py shell "$@"

# Update translation files
[group('development')]
[working-directory("src")]
makemessages:
    just run makemessages --keep-pot --all

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
djhtml *args:
    uv run djlint --reformat --format-js --format-css src/ {{ args }}

# Run all formatters and linters
[group('linting')]
[parallel]
fmt: black djhtml isort && flake8

# Run all code quality checks
[group('linting')]
[parallel]
check: black-check isort-check djhtml-check flake8 && check-done

[private]
check-done:
    echo '{{ GREEN }}All checks passed{{ NORMAL }}'

# Remove Python caches, build artifacts, and coverage reports
[group('development')]
clean:
    -find . -type d -name __pycache__ -exec rm -rf {} +
    -find . -type f -name "*.pyc" -delete
    -find . -type d -name "*.egg-info" -exec rm -rf {} +
    -rm -rf .pytest_cache .coverage htmlcov dist build

# Bump version using bumpver
[group('development')]
release *args:
    uv run bumpver update {{ args }}

# Run the test suite
[group('tests')]
[working-directory(".")]
test *args:
    uv run pytest {{ args }}

# Run tests with coverage report
[group('tests')]
test-coverage *args:
    just test --cov=src --cov-report=html --cov-report=term {{ args }}

# Show test coverage report in browser
[group('tests')]
[script('sh')]
test-coverage-report: test-coverage
    if [ -f "htmlcov/index.html" ]; then
        open htmlcov/index.html 2>/dev/null || \
        xdg-open htmlcov/index.html 2>/dev/null || \
        echo "Coverage report: htmlcov/index.html"
    else
        echo "No coverage report found. Run just test-coverage first."
    fi

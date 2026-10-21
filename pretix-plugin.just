set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set positional-arguments
set default-list

uv_dev := "uv run --extra=dev"

# Run ruff format
[group('linting')]
format *args=".":
    {{ uv_dev }} ruff format "$@"

# Run ruff check
[group('linting')]
check *args=".":
    {{ uv_dev }} ruff check "$@"

# Format Django templates with djangofmt.
[group('linting')]
djangofmt *args="":
    -{{ uv_dev }} djangofmt {{ args }} .

[group('linting')]
djangofmt-check:
    {{ uv_dev }} djangofmt --check . || (echo "HTML templates are not formatted. Run 'just djangofmt' to fix." && exit 1)

# Run all formatters and linters
[group('linting')]
fmt: (check "--fix") format djangofmt && fmt-done

[private]
fmt-done:
    echo '{{ GREEN }}Formatting complete{{ NORMAL }}'

# Run all code quality checks
[group('linting')]
fmt-check: (format "--check") check djangofmt-check && check-done

[private]
check-done:
    echo '{{ GREEN }}All checks passed{{ NORMAL }}'

# Run tests (installs pretix if not already present)
[group('tests')]
test *args: ensure-pretix
    {{ uv_dev }} pytest "$@"

# Install pretix from git
[group('development')]
install-pretix:
    uv pip install "pretix[dev] @ git+https://github.com/pretix/pretix@master"

# Install a local editable copy of pretix (for development)
[group('development')]
install-pretix-local path="../../..":
    uv pip install -e "{{ path }}[dev]"

# Ensure pretix is importable, installing it from git if needed
[private]
ensure-pretix:
    {{ uv_dev }} python -c "import pretix" 2>/dev/null || just install-pretix

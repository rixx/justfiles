set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Run the development server or other Django commands
[group('development')]
[working-directory("src")]
run *args="runserver":
    uv run --frozen --extra=dev manage.py {{ args }}

# Start a debugging SMTP server on localhost:1025
[group('development')]
mail:
    uv run --frozen python -m aiosmtpd -n -l localhost:1025

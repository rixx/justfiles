set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Run syntax check and ansible-lint on roles, playbooks, and host_vars
[group('quality')]
fmt:
    uv run ansible-playbook --syntax-check playbooks/*.yml
    uv run ansible-lint roles playbooks host_vars
    just check-handlers
    @echo '{{ GREEN }}All checks passed{{ NORMAL }}'

# Detect handler names that collide between roles sharing a play
[group('quality')]
check-handlers:
    uv run python scripts/check-handler-collisions.py

# Deploy to a server: just deploy playbooks/atlas.yml --tags pretalxupdate
[group('deploy')]
[positional-arguments]
deploy *args:
    uv run ansible-playbook --vault-password-file=.vault_password.sh "$@"

# Run in adhoc mode: just adhoc pretalx -a "df -h"
# Use -f {threads} for parallel runs
[group('deploy')]
[positional-arguments]
adhoc *args:
    uv run ansible --vault-password-file=.vault_password.sh "$@"

# Run ansible-vault: just vault edit host_vars/atlas/vault.yml
[arg('cmd', pattern='edit|view|encrypt|decrypt|encrypt_string|rekey|create')]
[group('deploy')]
[positional-arguments]
vault cmd *args:
    uv run ansible-vault {{ cmd }} --vault-password-file=.vault_password.sh "${@:2}"

set shell := ["bash", "-euo", "pipefail", "-c"]
set fallback := true

[private]
default:
    @just --list

# Run syntax check and ansible-lint on roles, playbooks, and host_vars
[group('quality')]
fmt:
    uv run --frozen ansible-playbook --syntax-check playbooks/*.yml
    uv run --frozen ansible-lint roles playbooks host_vars
    @echo '{{ GREEN }}All checks passed{{ NORMAL }}'

# Install external roles from requirements.yml
[group('setup')]
install:
    uv run --frozen ansible-galaxy install -r requirements.yml -p external_roles --force

# Deploy to a server: just deploy playbooks/atlas.yml --tags pretalxupdate
[group('deploy')]
deploy *args:
    uv run --frozen ansible-playbook --vault-password-file=.vault_password.sh {{ args }}

# Run in adhoc mode: just adhoc pretalx -a "'df -h'"
# Note: quote -a arguments twice due to just's argument handling
# Use -f {threads} for parallel runs
[group('deploy')]
adhoc *args:
    uv run --frozen ansible --vault-password-file=.vault_password.sh {{ args }}

# Run ansible-vault: just vault edit host_vars/atlas/vault.yml
[group('deploy')]
[arg('cmd', pattern='edit|view|encrypt|decrypt|encrypt_string|rekey|create')]
vault cmd *args:
    uv run --frozen ansible-vault {{ cmd }} --vault-password-file=.vault_password.sh {{ args }}

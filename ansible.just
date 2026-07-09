set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Run syntax check and ansible-lint on roles, playbooks, and host_vars
[group('quality')]
fmt:
    uv run ansible-playbook --syntax-check playbooks/*.yml
    uv run ansible-lint roles playbooks host_vars
    @echo '{{ GREEN }}All checks passed{{ NORMAL }}'

# Deploy to a server: just deploy playbooks/atlas.yml --tags pretalxupdate
[group('deploy')]
deploy *args:
    uv run ansible-playbook --vault-password-file=.vault_password.sh {{ args }}

# Run in adhoc mode: just adhoc pretalx -a "'df -h'"
# Note: quote -a arguments twice due to just's argument handling
# Use -f {threads} for parallel runs
[group('deploy')]
adhoc *args:
    uv run ansible --vault-password-file=.vault_password.sh {{ args }}

# Run ansible-vault: just vault edit host_vars/atlas/vault.yml
[arg('cmd', pattern='edit|view|encrypt|decrypt|encrypt_string|rekey|create')]
[group('deploy')]
vault cmd *args:
    uv run ansible-vault {{ cmd }} --vault-password-file=.vault_password.sh {{ args }}

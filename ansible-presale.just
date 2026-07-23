set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

playbooks := "apt-upgrade.yml backend.yml backups.yml proxy.yml staticfiles.yml"

# Run syntax check and ansible-lint on roles and playbooks
[group('quality')]
fmt:
    uv run ansible-playbook -i cccv_inventory --syntax-check {{ playbooks }}
    uv run ansible-lint roles {{ playbooks }}
    @echo '{{ GREEN }}All checks passed{{ NORMAL }}'

# Deploy to a server: just deploy backend.yml --tags pretixupdate
[group('deploy')]
[positional-arguments]
deploy *args:
    uv run ansible-playbook -i cccv_inventory "$@"

# Run in adhoc mode: just adhoc backend -a "df -h"
# Use -f {threads} for parallel runs
[group('deploy')]
[positional-arguments]
adhoc *args:
    uv run ansible -i cccv_inventory "$@"

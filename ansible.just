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

# Recent rspamd verdicts (time, score, action, sender, rcpt, subject, top symbols): just rspamd-history [n]
[group('mail')]
rspamd-history n="40":
    just adhoc tonks -m shell -a "curl -s localhost:11334/history" \
        | tail -n +2 \
        | jq -r --argjson n {{ n }} '.rows | sort_by(.unix_time) | .[-$n:] | .[] | [(.unix_time | localtime | strftime("%m-%d %H:%M")), (.score * 10 | round / 10 | tostring), .action, .sender_smtp, (.rcpt_smtp // [] | join(",")), (.subject // "" | .[0:40]), (.symbols | to_entries | sort_by(-(.value.score | fabs)) | .[0:8] | map("\(.key)(\(.value.score * 10 | round / 10))") | join(" "))] | @tsv'

# Re-score a stored mail file against the current live rspamd rules: just rspamd-check <file.eml>
[group('mail')]
rspamd-check file:
    just adhoc tonks -m copy -a "src='{{ file }}' dest=/tmp/rspamd-check.eml mode=0600"
    just adhoc tonks -m shell -a "rspamc symbols /tmp/rspamd-check.eml; rm -f /tmp/rspamd-check.eml"

# Instant PromQL query against Prometheus on jorge: just prom 'up{job="node"}'
# Single quotes cannot appear in the query; use double quotes for label values
[group('monitoring')]
[positional-arguments]
prom query:
    just adhoc jorge -m shell -a "curl -s -G --data-urlencode 'query=$1' localhost:9090/api/v1/query" \
        | tail -n +2 \
        | jq -r 'if .status != "success" then "ERROR: \(.errorType // ""): \(.error // .status)" elif .data.resultType == "vector" then (.data.result[] | "\(.metric.__name__ // "")\(.metric | del(.__name__) | if length > 0 then "{\(to_entries | map("\(.key)=\"\(.value)\"") | join(","))}" else "" end)\t\(.value[1])") elif .data.resultType == "scalar" then .data.result[1] else .data end'

# Run ansible-vault: just vault edit host_vars/atlas/vault.yml
[arg('cmd', pattern='edit|view|encrypt|decrypt|encrypt_string|rekey|create')]
[group('deploy')]
[positional-arguments]
vault cmd *args:
    uv run ansible-vault {{ cmd }} --vault-password-file=.vault_password.sh "${@:2}"

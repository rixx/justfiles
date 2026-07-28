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
    just journal-canary
    @echo '{{ GREEN }}All checks passed{{ NORMAL }}'

# Detect handler names that collide between roles sharing a play
[group('quality')]
check-handlers:
    uv run python scripts/check-handler-collisions.py

# Validate journal-brief exclusion rules against the never-ignore canary corpus
[group('quality')]
journal-canary:
    uv run python scripts/journal-brief-canary.py

# Pull new journal entries (since the last collect) from a host into
# .journal-dumps/<host>-<stamp>.log: just journal-brief-collect tonks
[group('monitoring')]
[positional-arguments]
journal-brief-collect host:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$1
    stamp=$(date +%F-%H%M%S)
    f="/var/tmp/journal-brief/dump-$stamp.log"
    just adhoc-sh "$host" "mkdir -p /var/tmp/journal-brief; journal-brief > $f 2>&1 || echo \"journal-brief failed: rc=\$?\" >> $f; find /var/tmp/journal-brief -type f -mtime +7 -delete" -b > /dev/null
    just adhoc "$host" -m fetch -a "src=$f dest=.journal-dumps/$host-$stamp.log flat=yes" -b > /dev/null
    wc -l ".journal-dumps/$host-$stamp.log"

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

# Run a compound shell command remotely with NO extra quoting layers (pipes, $vars,
# quotes all pass through verbatim): just adhoc-sh tonks 'key=$(cmd); echo "$key" | grep x' [-b] [ansible flags]
[group('deploy')]
[positional-arguments]
adhoc-sh host cmd *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$1; cmd=$2; shift 2
    tmp=$(mktemp --suffix=.sh)
    trap 'rm -f "$tmp"' EXIT
    printf '#!/bin/sh\n%s\n' "$cmd" > "$tmp"
    uv run ansible --vault-password-file=.vault_password.sh "$host" -m script -a "$tmp" "$@"

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

# Manage DNS records at INWX. Credentials + TOTP secret come from pass (web/inwx.de).
# Examples: just dns list rixx.de [A [name]]
#           just dns create rixx.de A grist-temp 2.28.2.63 [--ttl 3600]
#           just dns delete rixx.de A grist-temp   (or: delete rixx.de --id 123)
[group('dns')]
[positional-arguments]
dns *args:
    uv run scripts/dns.py "$@"

# All Grist accounts that ever logged in, with their team-org roles (the
# admin-panel user list is enterprise-only; this reads the home DB instead)
[group('grist')]
grist-users:
    just adhoc grist -m shell -a "sqlite3 -header -column /opt/grist/data/home.sqlite3 'select u.id, u.name, l.email, (select group_concat(g.name) from group_users gu join groups g on g.id = gu.group_id join acl_rules a on a.group_id = g.id where gu.user_id = u.id and a.org_id = 3) as org_roles from users u left join logins l on l.user_id = u.id where u.id > 4'" -b \
        | tail -n +2

# Run ansible-vault: just vault edit host_vars/atlas/vault.yml
[arg('cmd', pattern='edit|view|encrypt|decrypt|encrypt_string|rekey|create')]
[group('deploy')]
[positional-arguments]
vault cmd *args:
    uv run ansible-vault {{ cmd }} --vault-password-file=.vault_password.sh "${@:2}"

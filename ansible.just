set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Run syntax check and ansible-lint on roles, playbooks, and host_vars
[group('quality')]
fmt:
    uv run python scripts/lint.py -q --offline roles playbooks host_vars
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
[doc('Pull new journal entries from a host into .journal-dumps/')]
[group('monitoring')]
[positional-arguments]
journal-brief-collect host:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$1
    stamp=$(date +%F-%H%M%S)
    f="/var/tmp/journal-brief/dump-$stamp.log"
    just sh "$host" "mkdir -p /var/tmp/journal-brief; journal-brief > $f 2>&1 || echo \"journal-brief failed: rc=\$?\" >> $f; find /var/tmp/journal-brief -type f -mtime +7 -delete" > /dev/null
    just adhoc "$host" -m fetch -a "src=$f dest=.journal-dumps/$host-$stamp.log flat=yes" -b > /dev/null
    wc -l ".journal-dumps/$host-$stamp.log"

# Deploy to a server: just deploy playbooks/atlas.yml --tags pretalxupdate
[group('deploy')]
[positional-arguments]
deploy *args:
    uv run ansible-playbook --vault-password-file=.vault_password.sh "$@"

# Deploy every playbook in turn, passing flags through: just deploy-all --tags prometheus
# A failing host does not stop the fleet; the summary names it and the exit
# status is non-zero. (`import_playbook` cannot do this: a play whose only host
# fails ends the whole run, and every later playbook is skipped silently.)
[doc('Deploy all playbooks in turn, continuing past a failed host')]
[group('deploy')]
[positional-arguments]
deploy-all *args:
    #!/usr/bin/env bash
    set -uo pipefail
    failed=()
    for pb in playbooks/*.yml; do
        printf '\n\033[1m==> %s\033[0m\n' "$pb"
        uv run ansible-playbook --vault-password-file=.vault_password.sh "$pb" "$@" || failed+=("$pb")
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        printf '\n\033[31mfailed: %s\033[0m\n' "${failed[*]}"
        exit 1
    fi
    printf '\n\033[32mall playbooks succeeded\033[0m\n'

# Run a single ansible module: just adhoc atlas -m fetch -a "src=/etc/hosts dest=. flat=yes" -b
# For shell commands reach for `just sh` instead. Use -f {threads} for parallel runs.
[doc('Run a single ansible module against a host or group, raw output')]
[group('deploy')]
[positional-arguments]
adhoc *args:
    uv run ansible --vault-password-file=.vault_password.sh "$@"

# Run a shell command as root. A single host prints its plain output, ready to
# pipe; a group prefixes every line with "host<TAB>" to keep the hosts apart:
#   just sh tonks 'key=$(cmd); echo "$key" | grep x'
#   just sh all 'systemctl is-active caddy'
#   just sh mycroft 'id -un' --as-user     # connect as the login user, no root
#   just sh tonks 'rspamc stat' --json     # per-host dict instead of flat lines
# Pipes, $vars, command substitution and quotes of either kind pass through
# verbatim — the command travels as a script file. The exit status is the
# highest remote exit status (255 for an unreachable host), so a failure stops
# a pipeline instead of passing empty output along.
[doc('Run a shell command as root (--as-user to stay the login user)')]
[group('deploy')]
[no-exit-message]
[positional-arguments]
sh host cmd *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$1; cmd=$2; shift 2
    become=(-b); json=""; args=()
    for a in "$@"; do
        case "$a" in
            --as-user) become=() ;;
            --json) json=1 ;;
            *) args+=("$a") ;;
        esac
    done
    tmp=$(mktemp --suffix=.sh)
    trap 'rm -f "$tmp"' EXIT
    # Ansible runs the script on a pty, so systemd and git see a terminal and
    # start their pager, which then waits for a keypress nobody can send: the
    # command hangs until the ssh timeout with no output at all. `systemctl
    # cat`, `systemctl show` and `git log` all do this unless their output is
    # piped or redirected. Disabling the pager up front is the whole fix.
    printf '#!/bin/sh\nexport SYSTEMD_PAGER=cat PAGER=cat\n%s\n' "$cmd" > "$tmp"
    out=$(ANSIBLE_LOAD_CALLBACK_PLUGINS=1 ANSIBLE_STDOUT_CALLBACK=json ANSIBLE_DEPRECATION_WARNINGS=False \
        uv run ansible --vault-password-file=.vault_password.sh "$host" "${become[@]}" -f 20 \
        -m script -a "$tmp" ${args[@]+"${args[@]}"} 2>/dev/null) || true
    if ! hosts=$(printf '%s' "$out" | jq -e '.plays[0].tasks[0].hosts // empty' 2>/dev/null); then
        if printf '%s' "$out" | jq -e . > /dev/null 2>&1; then
            echo "just sh: no hosts matched '$host'" >&2
        else
            printf '%s\n' "${out:-just sh: no answer from ansible}" >&2
        fi
        exit 4
    fi
    # Drop the connection-teardown chatter that would otherwise outnumber the
    # actual output on a quiet command.
    noise='def demark: sub("\u001b\\]3008;end=[^\u001b]*(\u001b\\\\)?"; ""); def noise: test("^(Shared c|C)onnection to .* closed\\.$") or length == 0;'
    if [[ -n "$json" ]]; then
        printf '%s\n' "$hosts" | jq .
    elif [[ "$(printf '%s' "$hosts" | jq 'length')" == 1 ]]; then
        # One host answered, so its name carries no information: print the plain
        # command output. Remote stderr is already merged into stdout by the
        # script module; the exit status carries the failure.
        printf '%s' "$hosts" | jq -r "$noise"'
          .[] | if (.unreachable // false) then empty
                else (((.stdout_lines // []) + (.stderr_lines // []))
                      | map(demark) | map(select(noise | not)) | .[]) end'
        printf '%s' "$hosts" | jq -r '.[] | select(.unreachable // false)
          | "UNREACHABLE: \(.msg // "")"' >&2
    else
        printf '%s' "$hosts" | jq -r "$noise"'
          [to_entries[] | .key as $h | .value as $v
           | (($v.stdout_lines // []) + ($v.stderr_lines // [])
              | map(demark) | map(select(noise | not))) as $lines
           | if ($v.unreachable // false) then ["\($h)\tUNREACHABLE: \($v.msg // "")"]
             elif ($v.rc // 0) != 0 then ["\($h)\trc=\($v.rc)"] + ($lines | map("\($h)\t\(.)"))
             elif ($lines | length) == 0 then ["\($h)\t(no output)"]
             else ($lines | map("\($h)\t\(.)")) end]
          | flatten | .[]'
    fi
    exit "$(printf '%s' "$hosts" | jq '[.[] | if (.unreachable // false) then 255 else (.rc // 0) end] | max // 0')"

# Recent rspamd verdicts (time, score, action, sender, rcpt, subject, top symbols): just rspamd-history [n]
# The TSV summary keeps only the eight strongest symbols; add --json (in either
# argument slot) for the very same rows unformatted, so that every symbol and its
# score can be picked apart with jq:
#   just rspamd-history 100 --json | jq '.[] | select(.action == "add header") | .symbols'
[doc('Recent rspamd verdicts from tonks; --json for the raw rows')]
[group('mail')]
[positional-arguments]
rspamd-history n="40" format="":
    #!/usr/bin/env bash
    set -euo pipefail
    n="$1"; fmt="${2:-}"
    # Accept the flag in either slot, so plain `just rspamd-history --json` works too
    if [[ "$n" == "--json" || "$n" == "json" ]]; then fmt="$n"; n=40; fi
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then
        echo "rspamd-history: row count must be a number (got '$n')" >&2; exit 2
    fi
    if [[ -n "$fmt" && "$fmt" != "--json" && "$fmt" != "json" ]]; then
        echo "rspamd-history: only --json is supported here (got '$fmt')" >&2; exit 2
    fi
    rows=$(just adhoc tonks -m shell -a "curl -s localhost:11334/history" | tail -n +2)
    slice='.rows | sort_by(.unix_time) | .[-$n:]'
    if [[ -n "$fmt" ]]; then
        printf '%s' "$rows" | jq --argjson n "$n" "$slice"
    else
        printf '%s' "$rows" | jq -r --argjson n "$n" "$slice"' | .[] | [(.unix_time | localtime | strftime("%m-%d %H:%M")), (.score * 10 | round / 10 | tostring), .action, .sender_smtp, (.rcpt_smtp // [] | join(",")), (.subject // "" | .[0:40]), (.symbols | to_entries | sort_by(-(.value.score | fabs)) | .[0:8] | map("\(.key)(\(.value.score * 10 | round / 10))") | join(" "))] | @tsv'
    fi

# Replay a fail2ban filter template against a host's real logs, without
# touching the live jails. The template is rendered and installed under a
# throwaway name first, because INCLUDES like `before = postfix.conf` only
# resolve for files sitting inside /etc/fail2ban/filter.d/. Both the test
# filter and the journal dump are removed again, pass or fail.
# The journal unit comes from the jail template that declares [<name>]; pass
# it explicitly when there is none, or pass an absolute path for filters
# that watch a log file instead of the journal:
#   just f2b-test tonks roles/mailserver/templates/fail2ban/filter.d/postfix-postscreen.conf.j2
#   just f2b-test tonks roles/mailserver/templates/fail2ban/filter.d/foo.conf.j2 dovecot.service
#   just f2b-test atlas roles/pretalx.com/templates/fail2ban/filter.d/caddy-403.conf.j2 /var/log/caddy/pretalx.com.log
[doc("Replay a fail2ban filter template against a host's last 7 days of logs")]
[group('monitoring')]
[positional-arguments]
f2b-test host template source="":
    #!/usr/bin/env bash
    set -euo pipefail
    host="$1"; tpl="$2"; source="${3:-}"
    [[ -f "$tpl" ]] || { echo "f2b-test: no such template '$tpl'" >&2; exit 2; }
    name=$(basename "$tpl" .conf.j2)
    if [[ -z "$source" ]]; then
        jail=$(grep -rlF "[$name]" roles/*/templates/fail2ban/jail.d/ 2>/dev/null | head -1 || true)
        [[ -n "$jail" ]] || { echo "f2b-test: no jail template declares [$name]; pass a journal unit or log path" >&2; exit 2; }
        source=$(grep -oP '_SYSTEMD_UNIT=\K\S+' "$jail" | head -1 || true)
        [[ -n "$source" ]] || { echo "f2b-test: $jail has no journalmatch; pass a journal unit or log path" >&2; exit 2; }
        echo "f2b-test: journal unit $source (from $jail)" >&2
    fi
    dest="/etc/fail2ban/filter.d/zz-$name-test.conf"
    just adhoc "$host" -m template -a "src=$PWD/$tpl dest=$dest mode=0644" -b > /dev/null
    if [[ "$source" == /* ]]; then
        just sh "$host" "fail2ban-regex '$source' '$dest' --print-no-missed; rc=\$?; rm -f '$dest'; exit \$rc"
    else
        just sh "$host" "journalctl -u '$source' --since '7 days ago' -o short > /var/tmp/f2b-test.log; fail2ban-regex /var/tmp/f2b-test.log '$dest' --print-no-missed; rc=\$?; rm -f '$dest' /var/tmp/f2b-test.log; exit \$rc"
    fi

# Re-score a stored mail as the milter saw it: just rspamd-check <file.eml> [rspamc args]
# Strips our Received line and the verdict headers, rebuilds the envelope (see scripts/rspamd-check.py).
[doc('Re-score a stored mail file against the live rspamd rules, envelope rebuilt')]
[group('mail')]
[positional-arguments]
rspamd-check file *args:
    uv run scripts/rspamd-check.py "$@"

# Instant PromQL query against Prometheus on jorge: just prom 'up{job="node"}'
# Quotes of either kind are safe: jq encodes the query into the uri module's JSON
# arguments, so it travels as data and never reaches a shell (the old -m shell +
# curl form could not carry a single quote at all).
[doc('Instant PromQL query against Prometheus on jorge')]
[group('monitoring')]
[positional-arguments]
prom query:
    #!/usr/bin/env bash
    set -uo pipefail
    # The raw wrapper matters: ansible templates module arguments through
    # Jinja2, so a query containing doubled curly braces would be evaluated as
    # a template rather than sent to Prometheus.
    args=$(jq -n --arg q "$1" '{url: "http://localhost:9090/api/v1/query", method: "POST", body_format: "form-urlencoded", body: {query: ("{% raw %}" + $q + "{% endraw %}")}, return_content: true, status_code: [200, 400, 422, 503]}')
    out=$(ANSIBLE_LOAD_CALLBACK_PLUGINS=1 ANSIBLE_STDOUT_CALLBACK=json ANSIBLE_DEPRECATION_WARNINGS=False \
        uv run ansible --vault-password-file=.vault_password.sh jorge -m uri -a "$args")
    printf '%s' "$out" | jq -r '.plays[0].tasks[0].hosts.jorge as $h | if $h.json == null then "ERROR: \($h.msg // "no answer from jorge")" elif $h.json.status != "success" then "ERROR: \($h.json.errorType // ""): \($h.json.error // $h.json.status)" elif $h.json.data.resultType == "vector" then (if ($h.json.data.result | length) == 0 then "(no series)" else ($h.json.data.result[] | "\(.metric.__name__ // "")\(.metric | del(.__name__) | if length > 0 then "{\(to_entries | map("\(.key)=\"\(.value)\"") | join(","))}" else "" end)\t\(.value[1])") end) elif $h.json.data.resultType == "scalar" then $h.json.data.result[1] else $h.json.data end'

# Manage DNS records at INWX. Credentials + TOTP secret come from pass (web/inwx.de).
# Examples: just dns list rixx.de [A [name]]
#           just dns create rixx.de A grist-temp 2.28.2.63 [--ttl 3600]
# just dns delete rixx.de A grist-temp   (or: delete rixx.de --id 123)
[doc('Manage DNS records at INWX: list, create, delete')]
[group('dns')]
[positional-arguments]
dns *args:
    uv run scripts/dns.py "$@"

# All Grist accounts that ever logged in, with their team-org roles (the
# admin-panel user list is enterprise-only; this reads the home DB instead)
[doc('All Grist accounts that ever logged in, with their team-org roles')]
[group('grist')]
grist-users:
    just adhoc grist -m shell -a "sqlite3 -header -column /opt/grist/data/home.sqlite3 'select u.id, u.name, l.email, (select group_concat(g.name) from group_users gu join groups g on g.id = gu.group_id join acl_rules a on a.group_id = g.id where gu.user_id = u.id and a.org_id = 3) as org_roles from users u left join logins l on l.user_id = u.id where u.id > 4'" -b \
        | tail -n +2

# Pull a database host's postgres jsonlog into .pg-logs/<host>-<stamp>.json:
#   just pg-log atlas          -> everything still on disk
#   just pg-log atlas 24h      -> only the last 24 hours
# Interval accepts <number><unit> with unit m, h, d or w. Filtering and gzip run
# on the server, so only the selected window crosses the wire, and the result is
# newline-delimited JSON that pg-native tooling can read directly.
[doc('Pull a postgres jsonlog window into .pg-logs/')]
[group('monitoring')]
[positional-arguments]
pg-log host interval="":
    #!/usr/bin/env bash
    set -euo pipefail
    host="$1"; interval="${2:-}"
    if [[ -z "$interval" ]]; then
        cutoff=0; window="everything on disk"
    elif [[ "$interval" =~ ^([0-9]+)([mhdw])$ ]]; then
        case "${BASH_REMATCH[2]}" in
            m) unit=minutes ;;
            h) unit=hours ;;
            d) unit=days ;;
            w) unit=weeks ;;
        esac
        cutoff=$(date -d "${BASH_REMATCH[1]} $unit ago" +%s)
        window="last ${BASH_REMATCH[1]} $unit"
    else
        echo "pg-log: interval must look like 30m, 24h, 5d or 2w (got '$interval')" >&2
        exit 2
    fi
    stamp=$(date +%F-%H%M%S)
    mkdir -p .pg-logs
    dest=".pg-logs/$host-$stamp.json"
    if ! out=$(just adhoc "$host" -b -m script -a "scripts/pg-log-export.sh $cutoff" 2>&1); then
        msg=$(printf '%s' "$out" | grep -o 'pg-log-export: [^"\\]*' | head -1 || true)
        if [[ -n "$msg" ]]; then echo "pg-log: ${msg#pg-log-export: }" >&2; else echo "$out" >&2; fi
        exit 3
    fi
    just adhoc "$host" -b -m fetch -a "src=/var/tmp/pg-log-export.json.gz dest=$dest.gz flat=yes" > /dev/null
    gunzip -f "$dest.gz"
    lines=$(wc -l < "$dest")
    if [[ "$lines" -gt 0 ]]; then
        echo "$dest - $lines entries ($window), $(head -1 "$dest" | jq -r .timestamp) .. $(tail -1 "$dest" | jq -r .timestamp)"
    else
        echo "$dest - no entries in $window"
    fi

# Query statistics straight from a live database, for index hunting:
#   just pg-slow atlas                 -> pretalx, top 15
#   just pg-slow mycroft forgejo 30
# Top statements by total time from pg_stat_statements (cumulative since the
# last stats reset, so it sees fast-but-frequent queries the 100 ms slow log
# never logs), then the big tables ranked by full-table scans. The statement
# text is user input in disguise: literals come from requests, treat as data.
[doc('pg_stat_statements top-N and full-table scans on a live database')]
[group('monitoring')]
[positional-arguments]
pg-slow host db="pretalx" n="15":
    #!/usr/bin/env bash
    set -euo pipefail
    host="$1"; db="${2:-pretalx}"; n="${3:-15}"
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "pg-slow: n must be a number (got '$n')" >&2; exit 2; }
    just adhoc "$host" -b -m copy -a "src=scripts/pg-slow.sql dest=/var/tmp/pg-slow.sql mode=0644" > /dev/null
    just sh "$host" "sudo -u postgres psql -v n=$n -X -f /var/tmp/pg-slow.sql $db | cat; rm -f /var/tmp/pg-slow.sql"

# Summarise a pulled postgres log (see pg-log) down to one screen: errors, slow
# statements grouped by shape, temp-file spills, and plans whose row estimate
# missed badly: just pg-summary .pg-logs/atlas-2026-07-31-140158.json
# Each shape row is numbered; --shape N prints one in full, with the hour
# histogram and the query_id to grep the pull by.
[doc('Summarise a pulled postgres log down to one screen')]
[group('monitoring')]
pg-summary file *args:
    uv run scripts/pg-log-summary.py '{{ file }}' {{ args }}

# Pull the live Grafana dashboards back into roles/monitoring/files/dashboards/.
# Dashboards are provisioned with allowUiUpdates, so click-ops edits live only in
# Grafana until this runs. Files are matched to dashboards by uid; admin credentials
# come from pass (web/grafana.rixx.de).
[doc('Pull live Grafana dashboards into the repo')]
[group('monitoring')]
grafana-pull:
    #!/usr/bin/env bash
    set -euo pipefail
    dir=roles/monitoring/files/dashboards
    declare -A file_for
    for f in "$dir"/*.json; do
        uid=$(jq -r '.uid // empty' "$f")
        [[ -n "$uid" ]] || { echo "grafana-pull: $f has no uid" >&2; exit 2; }
        file_for[$uid]=$f
    done
    umask 077
    rc=$(mktemp)
    trap 'rm -f "$rc"' EXIT
    printf 'user = "%s:%s"\n' \
        "$(pass show web/grafana.rixx.de | grep '^user:' | cut -d' ' -f2-)" \
        "$(pass show web/grafana.rixx.de | head -1)" > "$rc"
    api() { curl -sS --fail-with-body -K "$rc" "https://grafana.rixx.de$1"; }
    live=$(api '/api/search?type=dash-db')
    changed=0
    for uid in "${!file_for[@]}"; do
        f=${file_for[$uid]}
        if [[ -z "$(jq -r --arg u "$uid" '.[] | select(.uid == $u) | .uid' <<<"$live")" ]]; then
            echo "grafana-pull: $f (uid $uid) does not exist in Grafana" >&2
            continue
        fi
        comment=$(jq -r '.__comment // empty' "$f")
        # id and version are per-install bookkeeping and must not be provisioned.
        api "/api/dashboards/uid/$uid" \
            | jq -S --arg c "$comment" '.dashboard | del(.id, .version, .__comment)
                | if $c == "" then . else {__comment: $c} + . end' > "$f.pulled"
        if cmp -s "$f" "$f.pulled"; then
            rm -f "$f.pulled"
        else
            mv "$f.pulled" "$f"
            echo "updated $f"
            changed=1
        fi
    done
    jq -r --args '.[] | select(.uid as $u | ($ARGS.positional | index($u)) | not)
        | "untracked in Grafana: \(.title) (uid \(.uid))"' <<<"$live" "${!file_for[@]}"
    [[ $changed -eq 1 ]] || echo "no changes"

# Fetch a goaccess report for one of a host's caddy sites and open it:
#   just goaccess tonks                 -> list the sites that have a report
#   just goaccess tonks rixx            -> fetch .goaccess/tonks-rixx.html, open it
# just goaccess tonks rixx --refresh  -> regenerate on the host first (slow)
[doc("Fetch a goaccess report for one of a host's caddy sites and open it")]
[group('monitoring')]
[positional-arguments]
goaccess host site="" *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    host="$1"; site="${2:-}"; shift 2 || true
    dir=/var/lib/goaccess/reports
    if [[ " ${*} " == *" --refresh "* ]]; then
        just adhoc "$host" -m systemd_service -a "name=goaccess-caddy.service state=restarted" -b > /dev/null
    fi
    if [[ -z "$site" ]]; then
        just adhoc "$host" -m shell -a "ls -1 $dir | sed 's/\.html$//'" -b | tail -n +2
        exit 0
    fi
    mkdir -p .goaccess
    just adhoc "$host" -m fetch -a "src=$dir/$site.html dest=.goaccess/$host-$site.html flat=yes" -b > /dev/null
    echo ".goaccess/$host-$site.html"
    xdg-open ".goaccess/$host-$site.html" > /dev/null 2>&1 &

# Run ansible-vault: just vault edit host_vars/atlas/vault.yml
[arg('cmd', pattern='edit|view|encrypt|decrypt|encrypt_string|rekey|create')]
[group('deploy')]
[positional-arguments]
vault cmd *args:
    uv run ansible-vault {{ cmd }} --vault-password-file=.vault_password.sh "${@:2}"

# The per-server sub-accounts run borg serve --append-only, so their prunes
# only mark archives; compaction needs the unrestricted main account
[doc('Compact luggage borg repos (append-only prunes become permanent)')]
[group('deploy')]
[positional-arguments]
luggage-compact *hosts:
    #!/usr/bin/env bash
    set -u
    export PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.local/share/password-store}"
    rc=0
    for h in ${@:-atlas ikarus mycroft jorge tonks munin cord}; do
        printf '%s compacting %s\n' "$(date +%H:%M:%S)" "$h" >&2
        BORG_PASSCOMMAND="sh -c 'pass show server/luggage/$h | head -n1'" \
            borg compact --verbose --lock-wait 600 "ssh://luggage/./backups/$h/$h"
        c=$?
        [ "$c" -gt "$rc" ] && rc=$c
        [ "$c" -eq 0 ] || printf '%s %s failed with exit code %s\n' "$(date +%H:%M:%S)" "$h" "$c" >&2
    done
    exit $rc

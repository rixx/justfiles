# justfiles

My collection of actually-in-use justfiles, making it easier for me to change all the Python project justfiles at once
etc. Files get deployed on disk with ``just install`` if the repo exists.

## Common recipes

- ``just fmt`` runs auto-formatters and linters
- ``just check`` does the same as ``just fmt`` but with all the read-only flags applied
- ``just run``: Runs whatever the project live/dev server is
- ``just run [cmd]``: In Django projects, ``just run`` calls ``manage.py``, defaulting to ``runserver``, but replacing
  it with other commands, so e.g. ``just run makemigrations``

## Using this repo

```
just clean         # Show backup files that would be removed
just clean-confirm # Remove backup files created during install
just diff          # Show differences between repo and installed justfiles
just install       # Install all justfiles to their projects
just status        # Check status of all justfiles
```

## Style guide

Every justfile opens with a settings block for sane defaults (don't echo
commands before running them, fall back to parent justfiles, list available
recipes on bare `just`):

```just
set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list
```

Apart from that, justfiles should:

- Mark helpers and CI-only recipes `[private]` so they don't clutter `just --list`.
- Use `[group('...')]` to structure `just --list` output.
- Use `[script(...)]` rather than shebang recipes, and for bash scripts, open with `set -euo pipefail`.

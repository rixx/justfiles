export BIN := "../../.venv/bin"

check:
  uvx black --check pretix_scheduling/
  uvx isort --check --gitignore pretix_scheduling/
  uvx flake8 --extend-exclude .cache pretix_scheduling/

fix:
  uvx black pretix_scheduling/
  uvx isort --gitignore pretix_scheduling/

run *args="python":
  # run arbitrary bins in the venv, defaults to python
  $BIN/{{ args }}

test *args="":
  #!/usr/bin/env bash

  if [[ -n "{{ args }}" ]]; then
    $BIN/pytest {{ args }}
  else
    $BIN/coverage run --module pytest
    $BIN/coverage report
    $BIN/coverage html
  fi

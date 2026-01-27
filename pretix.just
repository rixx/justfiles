export RUN := "uv run --python=3.12"

default:
    @just --list

[working-directory("src")]
@run *args="runserver":
  uv run --extra=dev manage.py {{ args }}

@mail:
  uv run python -m smtpd -n -c DebuggingServer localhost:1025

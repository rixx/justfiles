[private]
default:
    @just --list

# Add a new CLA signer
add name path:
    mv "{{ path }}" "clas/{{ name }}.pdf"
    just update
    git add "clas/{{ name }}.pdf" .clabot
    git commit -m "Add {{ name }}"
    @echo "Done! Run 'git push' to publish the changes."

# Sync CLA signers from clas/ directory to .clabot
update:
    #!/usr/bin/env bash
    set -euo pipefail

    # Get all names from clas/ directory (strip .pdf suffix)
    cla_names=$(ls clas/ 2>/dev/null | sed 's/\.pdf$//' | sort)

    if [ -z "$cla_names" ]; then
        echo "No CLA files found in clas/"
        exit 0
    fi

    # Read current contributors from .clabot
    current_contributors=$(jq -r '.contributors[]' .clabot | sort)

    # Find names that need to be added
    new_names=""
    for name in $cla_names; do
        if ! echo "$current_contributors" | grep -qx "$name"; then
            new_names="$new_names $name"
            echo "Adding new contributor: $name"
        fi
    done

    if [ -z "$new_names" ]; then
        echo "All CLA signers are already in .clabot"
        exit 0
    fi

    # Add new names and sort the contributors array
    for name in $new_names; do
        jq --arg name "$name" '.contributors += [$name]' .clabot > .clabot.tmp && mv .clabot.tmp .clabot
    done

    # Sort the contributors array
    jq '.contributors |= sort' .clabot > .clabot.tmp && mv .clabot.tmp .clabot

    echo "Updated .clabot with new contributors"

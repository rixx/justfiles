set shell := ["bash", "-euo", "pipefail", "-c"]
set quiet
set fallback
set default-list

# Fetch a queue into data/, re-render and open the page
fetch queue *args:
    ./rt.py fetch {{ queue }} {{ args }}

# Render data/*.json into presale-history.html
render:
    ./rt.py render

# Open the rendered page
open:
    xdg-open presale-history.html

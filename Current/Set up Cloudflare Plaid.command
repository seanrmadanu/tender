#!/bin/zsh
cd "${0:A:h}"
export PATH="/Users/sean/.nvm/versions/node/v22.22.1/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
python3 scripts/configure-cloudflare.py
read -r "?Press Return to close."

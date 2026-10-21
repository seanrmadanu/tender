#!/bin/zsh
cd "${0:A:h}"
python3 scripts/configure-bank.py
read -r "?Press Return to close."

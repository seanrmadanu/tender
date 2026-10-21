#!/usr/bin/env python3
"""Configure Tender's personal bridge locally. Never print or rotate saved secrets."""
import base64
import getpass
import os
from pathlib import Path
import secrets
import sys
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'backend' / '.env'


def read_config():
    values = {}
    if CONFIG.exists():
        for line in CONFIG.read_text().splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                key, value = line.split('=', 1)
                values[key] = value
    return values


def save(values):
    # Reject characters that could alter the env-file structure.
    if any(any(c in value for c in '\r\n\x00\"\'`#$') for value in values.values()):
        raise ValueError('A value contains unsupported configuration characters.')
    temp = CONFIG.with_suffix('.env.tmp')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, 'w') as file:
        file.write('# Private Tender bridge configuration. Never share this file.\n')
        file.write(''.join(f'{key}={value}\n' for key, value in values.items()))
    temp.replace(CONFIG)


def main():
    values = read_config()
    cloudflare = '--cloudflare' in sys.argv
    defaults = {
        'PLAID_ENV': 'sandbox', 'PLAID_COUNTRY_CODES': 'US', 'PLAID_CLIENT_ID': '', 'PLAID_SECRET': '',
        'PLAID_REDIRECT_URI': '', 'TENDER_LINK_MODE': 'browser' if cloudflare else 'native', 'TENDER_PUBLIC_URL': '', 'TENDER_API_TOKEN': secrets.token_hex(32),
        'TENDER_ENCRYPTION_KEY': base64.b64encode(secrets.token_bytes(32)).decode(),
        'TENDER_USER_ID': 'tender-personal', 'TENDER_HOST': '127.0.0.1',
        'PORT': '8787', 'APPLE_TEAM_ID': 'M955JC8G35', 'APPLE_BUNDLE_ID': 'com.sean.tender',
    }
    for key, value in defaults.items():
        if not values.get(key):
            values[key] = value
    if cloudflare:
        values['TENDER_LINK_MODE'] = 'browser'
    if '--init' not in sys.argv:
        print('Tender bank setup — enter keys here, never in chat. Input for keys is hidden.')
        print('Open Plaid Dashboard → Build → Keys. Use Production keys for your existing Trial.' if cloudflare else 'Open Plaid Dashboard → Build → Keys. Start with Sandbox to test for free.')
        default_environment = 'production' if cloudflare else values['PLAID_ENV']
        environment = input(f"Environment [sandbox/production, default: {default_environment}]: ").strip() or default_environment
        if environment not in ('sandbox', 'production'):
            raise ValueError('Choose sandbox or production.')
        countries = input(f"Enabled bank countries [US, CA, or US,CA; current: {values['PLAID_COUNTRY_CODES']}]: " ).strip().upper() or values['PLAID_COUNTRY_CODES']
        if countries not in ('US', 'CA', 'US,CA', 'CA,US'):
            raise ValueError('Choose US, CA, or US,CA for countries enabled on your Plaid account.')
        values['PLAID_COUNTRY_CODES'] = countries
        changed_environment = environment != values['PLAID_ENV']
        values['PLAID_ENV'] = environment
        for key, label in [('PLAID_CLIENT_ID', 'Plaid client ID'), ('PLAID_SECRET', f'{environment} secret')]:
            entered = getpass.getpass(label + (' [Enter keeps saved value]' if values.get(key) and not changed_environment else '') + ': ').strip()
            if entered:
                values[key] = entered
            elif changed_environment and key == 'PLAID_SECRET':
                raise ValueError('Enter the secret for the selected environment.')
        redirect = '' if cloudflare else input('HTTPS redirect URL (Enter keeps current): ').strip()
        if redirect:
            url = urlparse(redirect)
            if url.scheme != 'https' or not url.hostname or url.username or url.password or not url.path.startswith('/plaid/'):
                raise ValueError('Use an HTTPS URL on your host with a /plaid/ path.')
            values['PLAID_REDIRECT_URI'] = redirect
        if not cloudflare and not values['PLAID_REDIRECT_URI']:
            raise ValueError('Native iOS Link setup needs your HTTPS OAuth redirect URL.')
        if not values['PLAID_CLIENT_ID'] or not values['PLAID_SECRET']:
            raise ValueError('Both Plaid keys are required.')
    # Do not silently move/lose an existing token store. New setups use one file per environment.
    if 'TENDER_DATA_FILE' not in values:
        values['TENDER_DATA_FILE'] = f"./data/bank-links-{values['PLAID_ENV']}.enc"
    elif '--init' not in sys.argv and changed_environment:
        values['TENDER_DATA_FILE'] = f"./data/bank-links-{values['PLAID_ENV']}.enc"
    save(values)
    print('Private backend/.env saved with owner-only permissions. Existing encryption and access keys preserved.')
    if '--init' not in sys.argv:
        print('Next: use the Cloudflare setup helper to upload private keys.' if cloudflare else 'Next: run npm start from backend/. On an iPhone, configure the HTTPS host and Universal Link first.')


if __name__ == '__main__':
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print('\nSetup cancelled. No configuration saved.')
    except Exception as error:
        print(f'Setup stopped: {error}', file=sys.stderr)
        sys.exit(1)

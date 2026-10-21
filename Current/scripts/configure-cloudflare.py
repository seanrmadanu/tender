#!/usr/bin/env python3
"""Enter Plaid credentials privately and upload them to the user's Tender Worker."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('bank_config', ROOT / 'scripts' / 'configure-bank.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


def main():
    worker = json.loads((ROOT / 'backend' / 'wrangler.jsonc').read_text())
    address = worker['vars']['TENDER_PUBLIC_URL']
    if 'SET-AFTER' in address:
        raise ValueError('Deploy the Cloudflare Worker before entering keys.')
    print('Tender — private Plaid setup')
    print('Destination: your Cloudflare Worker at ' + address)
    print('This uploads Plaid credentials and Tender keys as encrypted Worker secrets.')
    print('No paid plan is selected. Your Plaid Trial remains limited to 10 connections.')
    print('Use Production keys from your existing free Trial. Never paste keys into chat.')
    if '--upload-saved' not in sys.argv:
        sys.argv.append('--cloudflare')
        config.main()
    values = config.read_config()
    if values.get('PLAID_ENV') != worker['vars']['PLAID_ENV']:
        raise ValueError('The saved Plaid environment must match the Worker (production). No secrets uploaded.')
    names = ['PLAID_CLIENT_ID', 'PLAID_SECRET', 'TENDER_API_TOKEN', 'TENDER_ENCRYPTION_KEY']
    if any(not values.get(name) for name in names):
        raise ValueError('All four private keys must be configured. No secrets uploaded.')
    values['TENDER_PUBLIC_URL'] = address
    values['TENDER_LINK_MODE'] = 'browser'
    config.save(values)
    wrangler = ROOT / 'backend' / 'node_modules' / '.bin' / 'wrangler'
    env = {**os.environ, 'WRANGLER_SEND_METRICS': 'false'}
    # Pass secrets over stdin, never command arguments or temporary JSON files.
    result = subprocess.run([str(wrangler), 'secret', 'bulk'], cwd=ROOT / 'backend', env=env,
                            input=json.dumps({name: values[name] for name in names}), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError('Cloudflare did not accept the secrets. Check Wrangler login and retry. Private values were not printed.')
    print('Cloudflare secrets uploaded. Checking the authenticated bridge…')
    # Cloudflare can reject urllib's default client identifier (error 1010).
    request = urllib.request.Request(address + '/v1/status', headers={
        'Authorization': 'Bearer ' + values['TENDER_API_TOKEN'],
        'User-Agent': 'Tender-Setup/1.0',
        'Accept': 'application/json',
    })
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status = json.load(response)
    except urllib.error.HTTPError as error:
        raise ValueError(f'Keys uploaded, but bridge verification returned HTTP {error.code}. Saved keys are preserved; no need to re-enter them.') from None
    except (urllib.error.URLError, TimeoutError):
        raise ValueError('Keys uploaded, but the bridge connection check could not finish. Saved keys are preserved; retry when online.') from None
    if status.get('environment') != 'production' or status.get('linkMode') != 'browser':
        raise ValueError('The live bridge did not report the expected configuration.')
    print('Cloudflare secrets saved. The authenticated bridge is ready.')
    print('This does not connect a bank yet. No Trial connection has been created.')
    print('In Tender: Accounts → Connect with Plaid → Connection Setup.')
    print('Bridge address: ' + address)
    if sys.platform == 'darwin' and '--upload-saved' not in sys.argv:
        subprocess.run(['pbcopy'], input=values['TENDER_API_TOKEN'], text=True, check=True)
        print('The bridge access token is copied to your clipboard. Paste it only into Tender.')
        print('Save Connection Settings → Test Connection → Connect a Bank.')
    else:
        print('Use TENDER_API_TOKEN from your private backend/.env in Tender; never use the Plaid secret in the app.')


if __name__ == '__main__':
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print('Setup cancelled.')
    except ValueError as error:
        # Only explicit, nonsecret validation messages are surfaced here.
        print('Setup stopped: ' + str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('Setup is incomplete. Check the selected environment, keys, Cloudflare login, and connection. Your private values have not been printed.', file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Apply DogBar's commercial mode (Config/commercial.json) to an app's Info.plist before signing.

Free is the default. A free build carries no licensing keys, so it never checks a license and
nothing remote can switch its features off. Paid is only possible by editing the checked-in
config deliberately and supplying public licensing configuration; no private keys are accepted.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'Config/commercial.json'
FIELDS = {'apiURL', 'publicKey', 'keyID', 'environment', 'required'}
PAID_FIELDS = {'currency', 'priceCents', 'billing', 'checkoutURL', 'freeUserTransition'}
LICENSE_KEYS = ('DogBarLicenseAPIURL', 'DogBarLicensePublicKey', 'DogBarLicenseKeyID',
                'DogBarLicenseEnvironment', 'DogBarLicenseRequired')
CHECKOUT_PATH = re.compile(r'/(?:checkout/)?hsc_[a-z0-9]+_[a-z0-9]+/?')


def load_policy(path=POLICY):
    value = json.loads(Path(path).read_text())
    if not isinstance(value, dict) or set(value) != {'mode', 'paid'} or value['mode'] not in ('free', 'paid'):
        raise ValueError('Config/commercial.json must contain only mode (free|paid) and paid')
    paid = value['paid']
    if not isinstance(paid, dict) or set(paid) != PAID_FIELDS:
        raise ValueError('The paid block must contain exactly: ' + ', '.join(sorted(PAID_FIELDS)))
    if paid['currency'] != 'USD' or paid['billing'] != 'one-time':
        raise ValueError('Only a one-time USD price is supported')
    if type(paid['priceCents']) is not int or paid['priceCents'] <= 0:
        raise ValueError('priceCents must be a positive integer')
    for key in ('checkoutURL', 'freeUserTransition'):
        if paid[key] is not None and (not isinstance(paid[key], str) or not paid[key].strip()):
            raise ValueError(f'{key} must be null or a non-empty string')
    return value


def checkout(url, channel):
    parts = urlsplit(url)
    hosts = ('pay.paddle.io',) if channel == 'stable' else ('pay.paddle.io', 'sandbox-pay.paddle.io')
    if parts.scheme != 'https' or parts.hostname not in hosts or parts.port or parts.username or parts.password \
            or parts.query or parts.fragment or not CHECKOUT_PATH.fullmatch(parts.path):
        raise ValueError('checkoutURL must be a Paddle hosted-checkout URL' + (' on pay.paddle.io' if channel == 'stable' else ''))


def load(path):
    value = json.loads(Path(path).read_text())
    if not isinstance(value, dict) or set(value) != FIELDS:
        raise ValueError('License configuration must contain exactly the five public configuration fields')
    url = urlsplit(value['apiURL'])
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
        raise ValueError('License API must be an HTTPS origin')
    key = value['publicKey']
    if not isinstance(key, str) or not re.fullmatch(r'[A-Za-z0-9_-]{43}', key) or len(base64.urlsafe_b64decode(key + '=')) != 32:
        raise ValueError('Expected a raw Ed25519 public key encoded as base64url')
    if value['environment'] not in ('sandbox', 'live') or type(value['required']) is not bool:
        raise ValueError('Invalid license environment or required flag')
    if not isinstance(value['keyID'], str) or not re.fullmatch(r'[A-Za-z0-9._-]{1,80}', value['keyID']):
        raise ValueError('Invalid license key ID')
    return {
        'DogBarLicenseAPIURL': value['apiURL'].rstrip('/'), 'DogBarLicensePublicKey': key,
        'DogBarLicenseKeyID': value['keyID'], 'DogBarLicenseEnvironment': value['environment'],
        'DogBarLicenseRequired': value['required']
    }


def mode(policy):
    """DOGBAR_COMMERCIAL_MODE may only force a free build (for local work); paid comes from the config."""
    override = os.environ.get('DOGBAR_COMMERCIAL_MODE')
    if override not in (None, '', 'free'):
        raise ValueError('DOGBAR_COMMERCIAL_MODE can only be "free"; switch to paid in Config/commercial.json')
    return 'free' if override == 'free' else policy['mode']


def fields(channel, policy=None):
    """The Info.plist keys for this channel, or an error before anything is signed."""
    policy = policy or load_policy()
    path = os.environ.get('DOGBAR_LICENSE_CONFIG')
    if mode(policy) == 'free':
        if path:
            raise ValueError('This is a free build; unset DOGBAR_LICENSE_CONFIG instead of embedding licensing')
        return {'DogBarCommercialMode': 'free'}
    paid = policy['paid']
    if not path:
        raise ValueError('Paid mode needs DOGBAR_LICENSE_CONFIG (the exported public licensing configuration)')
    if paid['checkoutURL'] is None:
        raise ValueError('Paid mode needs a verified checkoutURL; a build must never advertise an unavailable purchase')
    checkout(paid['checkoutURL'], channel)
    if paid['freeUserTransition'] is None:
        raise ValueError('Paid mode needs an owner-approved freeUserTransition for people already using the free build')
    values = load(path)
    if not values['DogBarLicenseRequired']:
        raise ValueError('A paid build must require activation')
    if channel == 'stable' and values['DogBarLicenseEnvironment'] != 'live':
        raise ValueError('Stable releases cannot use sandbox licensing')
    return {'DogBarCommercialMode': 'paid', **values}


def apply(info, channel):
    for key in LICENSE_KEYS + ('DogBarCommercialMode',):
        info.pop(key, None)
    info.update(fields(channel))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plist', type=Path, required=True)
    parser.add_argument('--channel', choices=['development', 'preview', 'stable'], required=True)
    args = parser.parse_args()
    info = plistlib.loads(args.plist.read_bytes())
    apply(info, args.channel)
    args.plist.write_bytes(plistlib.dumps(info))

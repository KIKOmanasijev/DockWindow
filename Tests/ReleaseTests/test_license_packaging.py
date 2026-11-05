import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('license_packaging', Path(__file__).resolve().parents[2] / 'Scripts/license_packaging.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

CHECKOUT = 'https://pay.paddle.io/hsc_01abc_def'

def policy(mode='free', **paid):
    value = dict(currency='USD', priceCents=399, billing='one-time', checkoutURL=None, freeUserTransition=None)
    value.update(paid)
    return dict(mode=mode, paid=value)

class LicensePackagingTests(unittest.TestCase):
    def fixture(self, directory, **changes):
        value = dict(apiURL='https://licenses.example.com', publicKey='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', keyID='test-1', environment='live', required=True)
        value.update(changes)
        path = Path(directory) / 'public-config.json'
        path.write_text(json.dumps(value))
        return path

    def test_checked_in_policy_is_free(self):
        value = m.load_policy()
        self.assertEqual(value['mode'], 'free')
        with patch.dict(m.os.environ, {}, clear=True):
            info = {'CFBundleName': 'DogBar', 'DogBarLicenseRequired': True}
            m.apply(info, 'stable')
            self.assertEqual(info, {'CFBundleName': 'DogBar', 'DogBarCommercialMode': 'free'})

    def test_free_build_refuses_license_configuration(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(m.os.environ, {'DOGBAR_LICENSE_CONFIG': str(self.fixture(temp))}):
            with self.assertRaises(ValueError): m.fields('stable', policy())

    def test_paid_needs_checkout_transition_and_license(self):
        with tempfile.TemporaryDirectory() as temp:
            path = str(self.fixture(temp))
            for value, env in ((policy('paid', checkoutURL=CHECKOUT, freeUserTransition='approved'), {}),
                               (policy('paid', freeUserTransition='approved'), {'DOGBAR_LICENSE_CONFIG': path}),
                               (policy('paid', checkoutURL=CHECKOUT), {'DOGBAR_LICENSE_CONFIG': path}),
                               (policy('paid', checkoutURL='https://example.com/buy', freeUserTransition='approved'), {'DOGBAR_LICENSE_CONFIG': path})):
                with self.subTest(value=value), patch.dict(m.os.environ, env, clear=True), self.assertRaises(ValueError):
                    m.fields('stable', value)
            with patch.dict(m.os.environ, {'DOGBAR_LICENSE_CONFIG': path}, clear=True):
                info = m.fields('stable', policy('paid', checkoutURL=CHECKOUT, freeUserTransition='approved'))
                self.assertEqual(info['DogBarCommercialMode'], 'paid')
                self.assertNotIn('priceCents', json.dumps(info))

    def test_paid_stable_rejects_sandbox_or_optional_activation(self):
        value = policy('paid', checkoutURL=CHECKOUT, freeUserTransition='approved')
        with tempfile.TemporaryDirectory() as temp:
            for changes in ({'environment': 'sandbox'}, {'required': False}):
                with self.subTest(changes=changes), patch.dict(m.os.environ, {'DOGBAR_LICENSE_CONFIG': str(self.fixture(temp, **changes))}, clear=True):
                    with self.assertRaises(ValueError): m.fields('stable', value)

    def test_environment_can_only_force_free(self):
        with patch.dict(m.os.environ, {'DOGBAR_COMMERCIAL_MODE': 'paid'}, clear=True), self.assertRaises(ValueError):
            m.fields('development', policy())
        with patch.dict(m.os.environ, {'DOGBAR_COMMERCIAL_MODE': 'free'}, clear=True):
            self.assertEqual(m.fields('development', policy('paid')), {'DogBarCommercialMode': 'free'})

    def test_private_material_or_http_origin_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            for changes in ({'privateKey':'never-allowed'}, {'apiURL':'http://example.com'}, {'publicKey':'invalid'}, {'required':'true'}):
                with self.subTest(changes=changes), self.assertRaises(ValueError): m.load(self.fixture(temp, **changes))

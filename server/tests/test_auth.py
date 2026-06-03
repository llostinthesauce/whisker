import unittest

from server.auth import AuthError, require_bearer


class AuthTests(unittest.TestCase):
    def test_accepts_matching_bearer_token(self):
        require_bearer("Bearer secret", "secret")

    def test_rejects_missing_prefix(self):
        with self.assertRaises(AuthError):
            require_bearer("secret", "secret")

    def test_rejects_wrong_token(self):
        with self.assertRaises(AuthError):
            require_bearer("Bearer wrong", "secret")

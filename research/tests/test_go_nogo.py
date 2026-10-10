import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import go_nogo  # noqa: E402


class TestGoNogo(unittest.TestCase):
    def test_go_nogo(self):
        self.assertTrue(go_nogo.decide(10, 20, 5))
        self.assertFalse(go_nogo.decide(10, 12, 5))


if __name__ == "__main__":
    unittest.main()

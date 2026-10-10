import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import kv_math  # noqa: E402

CONFIG = {
    "num_hidden_layers": 64,
    "full_attention_interval": 4,
    "num_key_value_heads": 4,
    "head_dim": 256,
    "linear_num_value_heads": 48,
    "linear_key_head_dim": 128,
    "linear_value_head_dim": 128,
}


class TestKvMath(unittest.TestCase):
    def test_full_layers(self):
        self.assertEqual(kv_math.full_attention_layers(CONFIG), 16)

    def test_kv_bf16(self):
        full_layers = kv_math.full_attention_layers(CONFIG)
        self.assertEqual(
            kv_math.kv_bytes_per_token(CONFIG, dtype_bytes=2), 65536
        )
        self.assertEqual(full_layers, 16)

    def test_kv_fp8(self):
        self.assertEqual(
            kv_math.kv_bytes_per_token(CONFIG, dtype_bytes=1), 32768
        )

    def test_state(self):
        self.assertEqual(kv_math.recurrent_state_bytes(CONFIG), 150994944)

    def test_text_config_nested(self):
        nested = {"text_config": dict(CONFIG)}
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False
        ) as fh:
            json.dump(nested, fh)
            path = fh.name
        try:
            cfg = kv_math.load_config(path)
        finally:
            os.remove(path)
        self.assertEqual(kv_math.full_attention_layers(cfg), 16)
        self.assertEqual(
            kv_math.kv_bytes_per_token(cfg, dtype_bytes=2), 65536
        )
        self.assertEqual(
            kv_math.kv_bytes_per_token(cfg, dtype_bytes=1), 32768
        )
        self.assertEqual(kv_math.recurrent_state_bytes(cfg), 150994944)

    def test_transfer_seconds(self):
        self.assertEqual(
            kv_math.transfer_seconds(650_000_000, 650_000_000), 1.0
        )


if __name__ == "__main__":
    unittest.main()

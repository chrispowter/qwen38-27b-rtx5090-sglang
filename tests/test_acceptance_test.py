from __future__ import annotations

import unittest

import acceptance_test


class AcceptanceHelpersTest(unittest.TestCase):
    def test_first_choice_returns_first_mapping(self) -> None:
        choice = acceptance_test.first_choice({"choices": [{"message": {"content": "ok"}}]})
        self.assertEqual(choice["message"]["content"], "ok")

    def test_first_choice_rejects_empty_response(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Invalid completion response"):
            acceptance_test.first_choice({"choices": []})


if __name__ == "__main__":
    unittest.main()

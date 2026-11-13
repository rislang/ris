#!/usr/bin/env python3
"""The ratchet rejects stale budgets in either direction."""
import unittest

from heap_check import TABLE, compare, sample_files


class HeapBudgetTest(unittest.TestCase):
    def test_sample_coverage(self):
        budgets = {line.split()[0] for line in TABLE.read_text().splitlines()
                   if line and not line.startswith("#")}
        self.assertEqual(set(sample_files()), budgets)

    def test_exact(self):
        for label in ("static sites", "allocations"):
            compare("sample", label, 3, 3)
            compare("sample", label, 0, 0)

    def test_stale(self):
        for label in ("static sites", "allocations"):
            for actual, budget, message in ((2, 3, "lower heap_budget.txt"),
                                            (4, 3, "> budget")):
                with self.subTest(label=label, actual=actual):
                    with self.assertRaisesRegex(RuntimeError, message):
                        compare("sample", label, actual, budget)


if __name__ == "__main__":
    unittest.main()

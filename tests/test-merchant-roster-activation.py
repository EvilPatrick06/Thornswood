"""The alpha roster cut is source policy, independent of server state."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/dev'))
spec = importlib.util.spec_from_file_location('population_activation', ROOT / 'scripts/dev/Build-NpcPopulation.py')
population = importlib.util.module_from_spec(spec)
spec.loader.exec_module(population)


class RosterActivationTests(unittest.TestCase):
    def test_exact_sixty_with_unchanged_ecology_and_reproducible_rebuild(self):
        original = json.loads((ROOT / 'game/data/npc-population.json').read_text(encoding='utf-8'))
        before = copy.deepcopy(original)
        result = population.activate_guild(original)
        self.assertEqual(original, before)
        self.assertEqual(result, population.activate_guild(result))
        selected = [row for row in result['npcs'] if row['role'] == 'trader' and row['keep']]
        self.assertEqual(len(selected), 60)
        self.assertEqual(len(result['merchantHistory']), 249)
        self.assertEqual({(row['hold'], row['guildRole']) for row in selected},
                         {(hold, role) for hold in population.BOOK_HOLDS.values() for role in population.ROLES})
        for old, new in zip(before['npcs'], result['npcs']):
            if old['role'] != 'trader':
                self.assertEqual(old, new)
            for key in ('ref', 'base', 'pos', 'cell', 'world', 'leash', 'returnMinutes'):
                self.assertEqual(old[key], new[key])
        self.assertEqual(result['summary']['retainedByRole']['trader'], 60)
        self.assertEqual(sum(row['count'] for row in result['locations']), result['summary']['retained'])

    def test_bad_binding_refuses_without_partial_source_changes(self):
        original = json.loads((ROOT / 'game/data/npc-population.json').read_text(encoding='utf-8'))
        original['npcs'] = [row for row in original['npcs'] if row['ref'] != '1a67c:Skyrim.esm']
        before = copy.deepcopy(original)
        with self.assertRaises(ValueError):
            population.activate_guild(original)
        self.assertEqual(original, before)


if __name__ == '__main__':
    unittest.main()

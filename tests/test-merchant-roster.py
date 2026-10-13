"""The six-trade cut changes interaction, never historical identity or ecology."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('merchant_roster', ROOT / 'scripts/dev/MerchantRoster.py')
roster = importlib.util.module_from_spec(spec)
spec.loader.exec_module(roster)


def policy():
    return json.loads((ROOT / 'game/data/merchant-roster.json').read_text(encoding='utf-8'))


def fixture():
    doc = policy()
    active = {row['reference']: row for row in doc['merchants']}
    rows = []
    for reference, base in doc['history']:
        assignment = active.get(reference)
        rows.append({'ref': reference, 'base': base, 'role': 'trader', 'keep': True,
                     'hold': assignment['hold'] if assignment else 'Whiterun',
                     'name': 'Old personal name', 'reason': 'Vendor', 'pos': [1, 2, 3],
                     'leash': 512, 'returnMinutes': 360, 'cell': '100:Skyrim.esm', 'world': None})
    rows.append({'ref': '200:Skyrim.esm', 'base': '300:Skyrim.esm', 'role': 'animal',
                 'keep': True, 'name': 'Goat', 'pos': [4, 5, 6], 'returnMinutes': 20})
    return rows, doc


class MerchantRosterTests(unittest.TestCase):
    def test_sixty_roles_preserve_history_placements_and_other_population(self):
        rows, doc = fixture()
        original = copy.deepcopy(rows)
        history = roster.apply_roster(rows, doc)
        self.assertEqual(history, doc['history'])
        self.assertEqual(sum(row['keep'] and row['role'] == 'trader' for row in rows), 60)
        self.assertEqual(sum(not row['keep'] for row in rows), 189)
        self.assertEqual(rows[-1], original[-1])
        self.assertEqual({(row['bookHold'], row['role']) for row in doc['merchants']},
                         {(hold, role) for hold in roster.BOOK_HOLDS for role in roster.ROLES})
        for before, after in zip(original[:-1], rows[:-1]):
            for field in ('ref', 'base', 'hold', 'pos', 'leash', 'returnMinutes', 'cell', 'world'):
                self.assertEqual(before[field], after[field])
            if after['keep']:
                self.assertEqual(after['displayName'], after['guildRole'])
                self.assertIn(after['guildRole'], roster.ROLES)
        self.assertEqual(doc, policy())

    def test_invalid_assignments_refuse_before_changing_any_row(self):
        changes = (
            lambda d: d.update(worldMode='new'),
            lambda d: d['merchants'].pop(),
            lambda d: d['merchants'].append(copy.deepcopy(d['merchants'][0])),
            lambda d: d['merchants'][0].update(role='Merchant'),
            lambda d: d['merchants'][0].update(role=[]),
            lambda d: d['merchants'][0].update(bookHold={}),
            lambda d: d['merchants'][0].update(role='Woodworker'),
            lambda d: d['merchants'][0].update(bookHold='riften'),
            lambda d: d['merchants'][0].update(hold='the Rift'),
            lambda d: d['merchants'][0].update(base='dead:Skyrim.esm'),
            lambda d: d['merchants'][0].update(reference='ff000001:Skyrim.esm'),
            lambda d: d['history'].pop(),
            lambda d: d['history'].append(copy.deepcopy(d['history'][0])),
            lambda d: d['history'][0].__setitem__(1, 'dead:Skyrim.esm'))
        for change in changes:
            rows, doc = fixture()
            before = copy.deepcopy(rows)
            change(doc)
            with self.subTest(change=change), self.assertRaises(ValueError):
                roster.apply_roster(rows, doc)
            self.assertEqual(rows, before)

    def test_missing_excluded_or_wrong_kind_selected_actor_refuses(self):
        for change in ('missing', 'excluded', 'animal'):
            rows, doc = fixture()
            selected = next(row for row in rows if row['ref'] == doc['merchants'][0]['reference'])
            if change == 'missing':
                rows.remove(selected)
            elif change == 'excluded':
                selected['keep'] = False
            else:
                selected['role'] = 'animal'
            before = copy.deepcopy(rows)
            with self.subTest(change=change), self.assertRaises(ValueError):
                roster.apply_roster(rows, doc)
            self.assertEqual(rows, before)

    def test_declared_identities_match_current_catalogued_source_records(self):
        payload = json.loads((ROOT / 'game/data/npc-population.json').read_text(encoding='utf-8'))
        rows = copy.deepcopy(payload['npcs'])
        roster.apply_roster(rows, policy())
        self.assertEqual(sum(row['keep'] and row['role'] == 'trader' for row in rows), 60)


if __name__ == '__main__':
    unittest.main()

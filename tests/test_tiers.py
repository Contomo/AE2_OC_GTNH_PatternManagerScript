import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source' / 'tools'))
from build_tiers import scrape, block_aliases
from unittest.mock import patch


class TierTests(unittest.TestCase):
    def quest(self, name, damage=1, ore=''):
        return {'tasks:9': {'0:10': {'requiredItems:9': {'0:10': {
            'id:8': name, 'Count:3': 1, 'Damage:2': damage, 'OreDict:8': ore}}}}}

    def test_only_actual_solid_task_requirements_classify_materials(self):
        reverse = {'test:parts@1': ('quorlium', 'ingot'),
                   'test:parts@2': ('quorlium', 'dust'),
                   'test:parts@3': ('quorlium', 'toolHeadHammer')}
        ignored = {'tasks:9': {}, 'rewards:9': self.quest('test:parts'),
                   'properties:10': self.quest('test:parts')}
        q = [('icon', 'ULV', ignored), ('dust', 'LV', self.quest('test:parts', 2)),
             ('tool', 'MV', self.quest('test:parts', 3)),
             ('later', 'UV', self.quest('TEST:PARTS')), ('solid', 'HV', self.quest('test:parts'))]
        result = scrape(q, reverse, {})
        self.assertEqual(result['quorlium']['tier'], 'HV')
        self.assertEqual(result['quorlium']['quest'], 'solid')
        self.assertEqual(result['quorlium']['form'], 'ingot')

    def test_oredict_requirements_use_registration_evidence(self):
        reverse = {'test:parts@1': ('quorlium', 'plate')}
        resources = {'test:parts@1': {'tags': ['plateQuorlium']}}
        result = scrape([('plate', 'IV', self.quest('minecraft:stone', ore='plateQuorlium'))],
                        reverse, resources)
        self.assertEqual(result['quorlium']['tier'], 'IV')
        self.assertFalse(scrape([('unknown', 'IV', self.quest('minecraft:stone', ore='plateMissing'))],
                               reverse, resources))

    def test_optional_ingredients_and_ambiguous_or_tasks_do_not_lower_a_tier(self):
        reverse = {'test:parts@1': ('quorlium', 'ingot')}
        optional = self.quest('test:parts')
        optional['tasks:9']['0:10']['taskID:8'] = 'bq_standard:optional_retrieval'
        either = self.quest('test:parts')
        either['tasks:9']['0:10']['requireOnlyOneItem:1'] = 1
        self.assertFalse(scrape([('optional', 'LV', optional), ('either', 'MV', either)], reverse, {}))
        result = scrape([('optional', 'LV', optional), ('required', 'UV', self.quest('test:parts'))], reverse, {})
        self.assertEqual(result['quorlium']['tier'], 'UV')

    def test_published_evidence_contains_quest_paths_and_no_material_examples(self):
        path = Path('data/material-tiers.json')
        if not path.exists(): self.skipTest('Quest source not installed')
        data = json.loads(path.read_text())
        self.assertEqual(data['packVersion'], '2.9.0-beta-3')
        self.assertTrue(data['materials'])
        for evidence in data['materials'].values():
            self.assertIn('/Quests/', evidence['quest'])
            self.assertTrue(evidence['item'])
        self.assertEqual(data['materials']['infinity']['tier'], 'UHV')

    def test_storage_blocks_need_matching_material_labels_and_simple_compression(self):
        reverse = {'test:ingot': ('quorlium', 'ingot')}
        resources = {'test:block': {'displayName': 'Block of Quorlium'},
                     'minecraft:diamond_block': {'displayName': 'Block of Diamond'}}
        def row(output):
            return {'inputs': [{'kind':'item','id':'test:ingot','amount':9}],
                    'outputs': [{'kind':'item','id':output,'amount':1}]}
        evidence = [('recipes', 'good', row('test:block')),
                    ('recipes', 'wrong-material', row('minecraft:diamond_block'))]
        with patch('build_tiers.records', return_value=iter(evidence)):
            block_aliases('unused', reverse, resources)
        self.assertEqual(reverse['test:block'], ('quorlium', 'block'))
        self.assertNotIn('minecraft:diamond_block', reverse)


if __name__ == '__main__': unittest.main()

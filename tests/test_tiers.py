import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source' / 'tools'))
from build_tiers import scrape, block_aliases, ore_aliases, inherit_tiers, ingredient_evidence, refine_processed_quest_tiers
from unittest.mock import patch


class TierTests(unittest.TestCase):
    def quest(self, name, damage=1, ore=''):
        return {'tasks:9': {'0:10': {'requiredItems:9': {'0:10': {
            'id:8': name, 'Count:3': 1, 'Damage:2': damage, 'OreDict:8': ore}}}}}

    def test_material_forms_include_dusts_but_not_icons_rewards_or_tool_heads(self):
        reverse = {'test:parts@1': ('quorlium', 'ingot'),
                   'test:parts@2': ('quorlium', 'dust'),
                   'test:parts@3': ('quorlium', 'toolHeadHammer')}
        ignored = {'tasks:9': {}, 'rewards:9': self.quest('test:parts'),
                   'properties:10': self.quest('test:parts')}
        q = [('icon', 'ULV', ignored), ('dust', 'LV', self.quest('test:parts', 2)),
             ('tool', 'MV', self.quest('test:parts', 3)),
             ('later', 'UV', self.quest('TEST:PARTS')), ('solid', 'HV', self.quest('test:parts'))]
        result = scrape(q, reverse, {})
        self.assertEqual(result['quorlium']['tier'], 'LV')
        self.assertEqual(result['quorlium']['quest'], 'dust')
        self.assertEqual(result['quorlium']['form'], 'dust')

    def test_oredict_requirements_use_registration_evidence(self):
        reverse = {'test:parts@1': ('quorlium', 'plate')}
        resources = {'test:parts@1': {'tags': ['plateQuorlium']}}
        result = scrape([('plate', 'IV', self.quest('minecraft:stone', ore='plateQuorlium'))],
                        reverse, resources)
        self.assertEqual(result['quorlium']['tier'], 'IV')
        self.assertFalse(scrape([('unknown', 'IV', self.quest('minecraft:stone', ore='plateMissing'))],
                               reverse, resources))

    def test_optional_and_alternative_forms_are_availability_evidence(self):
        reverse = {'test:parts@1': ('quorlium', 'ingot')}
        optional = self.quest('test:parts')
        optional['tasks:9']['0:10']['taskID:8'] = 'bq_standard:optional_retrieval'
        either = self.quest('test:parts')
        either['tasks:9']['0:10']['requireOnlyOneItem:1'] = 1
        self.assertEqual(scrape([('optional', 'LV', optional), ('either', 'MV', either)], reverse, {})['quorlium']['tier'], 'LV')
        result = scrape([('optional', 'LV', optional), ('required', 'UV', self.quest('test:parts'))], reverse, {})
        self.assertEqual(result['quorlium']['tier'], 'LV')

    def test_published_evidence_contains_quest_paths_and_no_material_examples(self):
        path = Path('data/material-tiers.json')
        if not path.exists(): self.skipTest('Quest source not installed')
        data = json.loads(path.read_text())
        self.assertEqual(data['packVersion'], '2.9.0-beta-3')
        self.assertTrue(data['materials'])
        for evidence in data['materials'].values():
            if evidence['kind'] == 'ore access estimate':
                self.assertTrue(evidence['source'] and evidence['dimension'] and evidence['accessSource'])
            else:
                self.assertIn('/Quests/', evidence['quest'])
                self.assertTrue(evidence['item'])
        self.assertEqual(data['materials']['infinity']['tier'], 'UHV')
        self.assertEqual(data['materials']['bedrockium']['tier'], 'EV')
        self.assertEqual(data['materials']['blackplutonium']['tier'], 'ZPM')
        self.assertEqual(data['materials']['blackplutonium']['dimension'], 'Triton')
        self.assertEqual(data['materials']['ironmagnetic']['tier'], 'ULV')
        self.assertIn('lead', data['materials'])
        self.assertNotEqual(data['materials'].get('neutronium', {}).get('tier'), 'EV')
        self.assertEqual(data['materials']['tungstencarbide']['tier'], 'EV')
        self.assertEqual(data['materials']['tungstencarbide']['kind'], 'production route estimate')
        self.assertTrue(data['materials']['tungstencarbide']['route'])

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


    def test_side_chapters_follow_all_prerequisites_and_or_uses_earliest_path(self):
        def q(refs, logic='AND'):
            return {'preRequisites:9': {str(n): {'questIDHigh:4': 0, 'questIDLow:4': r}
                    for n,r in enumerate(refs)}, 'properties:10': {'betterquesting:10': {'questLogic:8': logic}}}
        quests = {(0,1): ('early',q([])), (0,2): ('late',q([])),
                  (0,3): ('all',q([1,2])), (0,4): ('either',q([1,2],'OR')),
                  (0,5): ('unknown',q([99])), (0,6): ('cycle',q([6]))}
        tiers = {path:tier for path,tier,_ in inherit_tiers(quests,{(0,1):'LV',(0,2):'UV'})}
        self.assertEqual(tiers['all'],'UV'); self.assertEqual(tiers['either'],'LV')
        self.assertNotIn('unknown',tiers); self.assertNotIn('cycle',tiers)

    def test_ore_aliases_resolve_only_unambiguous_material_forms(self):
        reverse = {'test:a':('quorlium','plate'),'test:b':('other','plate')}
        resources = {'test:a':{'tags':['plateQuorlium','plateAnyMetal']},
                     'test:b':{'tags':['plateAnyMetal']}}
        ore_aliases(reverse,resources)
        self.assertEqual(reverse['oredict:plateQuorlium'],('quorlium','plate'))
        self.assertNotIn('oredict:plateAnyMetal',reverse)

    def test_recipe_ingredients_require_all_alternatives_and_ignore_byproducts(self):
        reverse = {'test:rare':('rare','plate'), 'test:common':('common','plate'),
                   'test:ingot':('common','ingot')}
        quest = self.quest('test:device',0); quest['_tierAnchor'] = True
        def recipe(name, inputs, extra=False):
            outs = [{'id':'test:device','kind':'item','amount':1}]
            if extra: outs.append({'id':'test:byproduct','kind':'item','amount':1})
            return ('recipes',name,{'id':name,'eut':0,'kind':'crafting',
                    'inputs':[{'id':rid,'kind':'item','amount':1} for rid in inputs], 'outputs':outs})
        rows = [recipe('rare-route',['test:rare','test:common']),
                recipe('cheap-route',['test:common']), recipe('byproduct',['test:rare'], True),
                ('recipes','production',{'id':'production','eut':8,'kind':'gregtech_machine',
                 'inputs':[{'id':'test:dust','kind':'item','amount':1}],
                 'outputs':[{'id':'test:ingot','kind':'item','amount':1}]})]
        evidence = {}
        with patch('build_tiers.records',return_value=iter(rows)):
            ingredient_evidence('unused',[('quest','LV',quest)],reverse,evidence)
        self.assertIn('common',evidence); self.assertNotIn('rare',evidence)

    def test_recycling_an_expensive_machine_cannot_establish_material_availability(self):
        reverse = {'test:ingot': ('rare', 'ingot')}
        recipe = {'id': 'machine-recovery', 'machineType': 'Fluid Extractor', 'eut': 8,
                  'inputs': [{'id':'test:machine','kind':'item','amount':1}],
                  'outputs': [{'id':'test:ingot','kind':'item','amount':8},
                              {'id':'molten.polymer','kind':'fluid','amount':100}]}
        with patch('build_tiers.records',return_value=iter([('recipes','recovery',recipe)])):
            self.assertFalse(ingredient_evidence('unused',[],reverse,{}))

    def test_any_one_material_choice_does_not_classify_every_later_option(self):
        quest = self.quest('test:parts')
        task = quest['tasks:9']['0:10']
        task['requireOnlyOneItem:1'] = 1
        task['requiredItems:9']['1:10'] = {'id:8':'test:later','Damage:2':1,'Count:3':1}
        reverse = {'test:parts@1':('early','ingot'), 'test:later@1':('later','ingot')}
        self.assertFalse(scrape([('choose-one','LV',quest)],reverse,{}))

    def route(self, name, inputs, output, voltage, machine='Mixer'):
        return ('recipes', name, {'id': name, 'kind': 'gregtech_machine', 'machineType': machine,
                'eut': voltage, 'inputs': [{'id': item, 'kind': 'item', 'amount': 1} for item in inputs],
                'outputs': [{'id': output, 'kind': 'item', 'amount': 1}]})

    def test_late_part_quest_is_refined_by_creation_and_ingot_production_route(self):
        reverse = {'test:a': ('a', 'dust'), 'test:b': ('b', 'dust'),
                   'test:dust': ('alloy', 'dust'), 'test:hot': ('alloy', 'ingotHot'),
                   'test:ingot': ('alloy', 'ingot')}
        result = {'a': {'tier': 'HV'}, 'b': {'tier': 'LV'},
                  'alloy': {'tier': 'ZPM', 'form': 'foil', 'kind': 'quest item', 'quest': 'late'}}
        rows = [self.route('mix', ['test:a', 'test:b'], 'test:dust', 480),
                self.route('blast', ['test:dust'], 'test:hot', 1920, 'Blast Furnace'),
                self.route('cool', ['test:hot'], 'test:ingot', 120, 'Vacuum Freezer')]
        with patch('build_tiers.records', return_value=iter(rows)):
            refine_processed_quest_tiers('unused', reverse, result)
        evidence = result['alloy']
        self.assertEqual(evidence['tier'], 'EV')
        self.assertEqual(evidence['questTier'], 'ZPM')
        self.assertEqual(evidence['inputTiers'], {'a': 'HV', 'b': 'LV'})
        self.assertEqual(evidence['route'], ['mix', 'blast', 'cool'])

    def test_unknown_inputs_recycling_and_unseeded_cycles_cannot_lower_a_part_quest(self):
        reverse = {'test:dust': ('alloy', 'dust'), 'test:ingot': ('alloy', 'ingot'),
                   'test:plate': ('alloy', 'plate')}
        result = {'alloy': {'tier': 'UV', 'form': 'foil', 'kind': 'quest item', 'quest': 'late'}}
        rows = [self.route('unknown', ['test:unknown'], 'test:ingot', 8),
                self.route('recycle', ['test:plate'], 'test:ingot', 8, 'Arc Furnace'),
                self.route('cycle1', ['test:ingot'], 'test:dust', 8),
                self.route('cycle2', ['test:dust'], 'test:ingot', 8)]
        with patch('build_tiers.records', return_value=iter(rows)):
            refine_processed_quest_tiers('unused', reverse, result)
        self.assertEqual(result['alloy']['tier'], 'UV')

    def test_raw_ingot_quest_is_refined_through_alloy_blast_gas_and_cooling(self):
        reverse = {'test:base': ('base', 'dust'), 'test:dust': ('alloy', 'dust'),
                   'test:hot': ('alloy', 'ingotHot'), 'test:ingot': ('alloy', 'ingot')}
        result = {'base': {'tier': 'ZPM'},
                  'alloy': {'tier': 'UIV', 'form': 'ingot', 'kind': 'quest item', 'quest': 'late'}}
        blast = self.route('blast', ['test:dust'], 'test:hot', 1966080, 'Blast Furnace')
        blast[2]['inputs'].append({'id': 'gas', 'kind': 'fluid', 'amount': 100})
        gas = ('recipes', 'gas', {'id': 'gas', 'kind': 'world_fluid', 'eut': 0,
                                'inputs': [], 'outputs': [{'id': 'gas', 'kind': 'fluid'}]})
        rows = [self.route('mix', ['test:base'], 'test:dust', 122880), gas, blast,
                self.route('cool', ['test:hot'], 'test:ingot', 122880, 'Vacuum Freezer')]
        with patch('build_tiers.records', return_value=iter(rows)):
            refine_processed_quest_tiers('unused', reverse, result)
        evidence = result['alloy']
        self.assertEqual(evidence['tier'], 'UHV')
        self.assertEqual(evidence['questTier'], 'UIV')
        self.assertEqual(evidence['route'], ['mix', 'gas', 'blast', 'cool'])
        self.assertEqual(evidence['inputTiers'], {'base': 'ZPM'})

    def test_fluid_recycling_replication_and_zero_eut_special_machine_do_not_unlock_ingots(self):
        reverse = {'test:ingot': ('alloy', 'ingot')}
        result = {'alloy': {'tier': 'UIV', 'form': 'ingot', 'kind': 'quest item', 'quest': 'late'}}
        cast = self.route('cast', [], 'test:ingot', 8, 'Fluid Solidifier')
        cast[2]['inputs'] = [{'id': 'molten.alloy', 'kind': 'fluid'}]
        fake = ('recipes', 'special', {'id': 'special', 'kind': 'gregtech_machine',
                'machineType': 'Eye of Harmony', 'eut': 0, 'inputs': [],
                'outputs': [{'id': 'molten.alloy', 'kind': 'fluid'}]})
        replication = self.route('replicate', [], 'test:ingot', 8, 'Replicator')
        with patch('build_tiers.records', return_value=iter([cast, fake, replication])):
            refine_processed_quest_tiers('unused', reverse, result)
        self.assertEqual(result['alloy']['tier'], 'UIV')

    def test_production_refinement_keeps_later_ingredient_tier_and_existing_earlier_quest(self):
        reverse = {'test:a': ('a', 'dust'), 'test:ingot': ('alloy', 'ingot')}
        result = {'a': {'tier': 'LuV'},
                  'alloy': {'tier': 'UV', 'form': 'plate', 'kind': 'quest item', 'quest': 'late'}}
        rows = [self.route('alloy', ['test:a'], 'test:ingot', 8)]
        with patch('build_tiers.records', return_value=iter(rows)):
            refine_processed_quest_tiers('unused', reverse, result)
        self.assertEqual(result['alloy']['tier'], 'LuV')
        result['alloy'] = {'tier': 'EV', 'form': 'plate', 'kind': 'quest item', 'quest': 'earlier'}
        with patch('build_tiers.records', return_value=iter(rows)):
            refine_processed_quest_tiers('unused', reverse, result)
        self.assertEqual(result['alloy']['tier'], 'EV')

if __name__ == '__main__': unittest.main()

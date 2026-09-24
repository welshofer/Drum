import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

spec = importlib.util.spec_from_file_location('artifacts', 'scripts/benchmark-artifacts.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)

class EvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.area = Path('audit/validation/r5-fixtures')
        cls.area.mkdir(parents=True, exist_ok=True)
        a.start(cls.area, 'native,crt', 1)
        cls.running = json.loads((cls.area/'manifest.json').read_text())
        cls.raw = {
            'os':'Version 27.1 (Build 26B5043p)', 'scale':2, 'stagePixels':[2560,720],
            'paintEndpoint':a.ENDPOINT, 'resizeMethod':a.RESIZE,
            'environment':{'FAKE_CREDENTIAL':'fixture-private-marker'}, 'stages':[],
        }
        for mode in ['native','crt']:
            for workload in sorted(a.WORKLOADS):
                stage={'mode':mode,'workload':workload, **{k:1 for k in a.SCALARS},
                       **{k:[1,2,3] for k in a.SERIES}, 'terminalText':'fixture-private-marker'}
                cls.raw['stages'].append(stage)
        a.write_json(cls.area/'measurements.json',cls.raw)
        (cls.area/'build-test.log').write_text('warning: fixture tooling warning\nfixture-private-marker\n')
        (cls.area/'ready').write_text('12345\n')
        (cls.area/'private.trace').write_text('fixture-private-marker')
        a.finish(cls.area)
        cls.complete=json.loads((cls.area/'manifest.json').read_text())

    def test_numeric_summary_is_unchanged_by_sanitizing(self):
        clean=a.sanitized_report(self.raw)
        def summary(value):
            return subprocess.check_output(['python3','scripts/summarize-performance.py','/dev/stdin'], input=json.dumps(value),text=True)
        self.assertEqual(summary(self.raw),summary(clean))
        self.assertIn('2.00 / 3.00 / 3.00',summary(clean))
        self.assertIn('not rendered FPS',summary(clean))

    def test_export_has_only_whitelisted_files_and_fields(self):
        path=self.area/'exported'
        a.export(self.area,path)
        self.assertEqual({p.name for p in path.iterdir()},{'manifest.json','measurements.json','summary.md'})
        all_text=''.join(p.read_text() for p in path.iterdir())
        self.assertNotIn('fixture-private-marker',all_text)
        self.assertNotIn('FAKE_CREDENTIAL',all_text)
        m=json.loads((path/'manifest.json').read_text())
        self.assertEqual(m['measurements_sha256'],a.checksum(path/'measurements.json'))
        self.assertEqual(m['build_warning_count'],1)
        with self.assertRaises(ValueError): a.export(self.area,path)

    def test_incomplete_nan_and_missing_stages_are_rejected(self):
        with self.assertRaises(ValueError): a.sanitized_manifest(self.running)
        bad=copy.deepcopy(self.raw);bad['stages'][0]['captureMs']=[float('nan')]
        with self.assertRaises(ValueError): a.sanitized_report(bad)
        bad=copy.deepcopy(self.raw);bad['stages'].pop()
        with self.assertRaises(ValueError): a.check_coverage(bad,self.complete)

    def test_invalid_metadata_and_free_text_are_rejected(self):
        bad=copy.deepcopy(self.raw);bad['os']='fixture-private-marker'
        with self.assertRaises(ValueError): a.sanitized_report(bad)
        bad=copy.deepcopy(self.complete);bad['xcode_build']='fixture-private-marker'
        with self.assertRaises(ValueError): a.sanitized_manifest(bad)
        for modes in ['native,native','unknown','']:
            with self.assertRaises(ValueError): a.selected_modes(modes)

    def test_tampered_checksum_and_changed_sources_are_rejected(self):
        area=self.area/'tampered';area.mkdir()
        a.write_json(area/'manifest.json',self.complete)
        (area/'measurements.json').write_text('{}')
        with self.assertRaises(ValueError): a.export(area,area/'out')
        changed=dict(self.running,source_sha256='0'*64)
        a.write_json(area/'manifest.json',changed)
        with self.assertRaises(ValueError): a.finish(area)

if __name__=='__main__': unittest.main(verbosity=2)

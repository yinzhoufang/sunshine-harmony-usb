import contextlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src-tauri/resources/harmony-usb'))
from mapping_guard import MAPS, MappingGuard, mode_lock


@contextlib.contextmanager
def unlocked():
    yield True


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'transport-state.json'
        self.state()
        self.online = True
        self.rules = set(MAPS)
        self.calls = []
        self.guard = MappingGuard('hdc', self.path, runner=self.run_hdc,
                                  lock=unlocked, log=lambda *a, **kw: None)

    def state(self, mode='usb', device='tablet-1'):
        self.path.write_text(json.dumps(dict(mode=mode, device_id=device)), encoding='utf-8')

    def run_hdc(self, args):
        self.calls.append(args)
        if args == ['list', 'targets']:
            return 'tablet-1\nother-tablet' if self.online else '[Empty]'
        self.assertEqual(args[:2], ['-t', 'tablet-1'])
        if args[2:] == ['fport', 'ls']:
            return '\n'.join(f'tablet-1 tcp:{a} tcp:{b} [Reverse]' for a, b in self.rules)
        self.assertEqual(args[2], 'rport')
        self.rules.add(tuple(int(a.split(':')[1]) for a in args[3:]))
        return 'OK'

    def mutations(self):
        return [a for a in self.calls if 'rport' in a]

    def test_healthy_cycle_does_not_rebuild_any_rule(self):
        self.guard.check()
        self.assertEqual(self.mutations(), [])
        self.assertEqual(self.guard.last_status, 'ready')

    def test_complete_mapping_loss_recovers_once(self):
        self.rules.clear()
        self.guard.check()
        self.assertEqual(self.rules, set(MAPS))
        self.assertEqual(len(self.mutations()), 7)
        self.guard.check()
        self.assertEqual(len(self.mutations()), 7)

    def test_partial_loss_only_repairs_missing_rule(self):
        self.rules.remove(MAPS[3])
        self.guard.check()
        self.assertEqual(len(self.mutations()), 1)
        self.assertEqual(self.mutations()[0][-2:], ['tcp:47997', 'tcp:47997'])

    def test_disconnect_waits_then_reconnect_recovers(self):
        self.rules.clear()
        self.online = False
        self.guard.check()
        self.assertEqual(self.guard.last_status, 'waiting_device')
        self.assertEqual(self.mutations(), [])
        self.online = True
        self.guard.check()
        self.assertEqual(self.rules, set(MAPS))

    def test_lan_mode_never_calls_hdc(self):
        self.state('lan')
        self.guard.check()
        self.assertEqual(self.calls, [])

    def test_switch_mutex_prevents_repair(self):
        @contextlib.contextmanager
        def busy():
            yield False
        self.guard.lock = busy
        self.guard.check()
        self.assertEqual(self.calls, [])

    def test_foreign_mapping_is_not_deleted_or_overwritten(self):
        self.rules.remove(MAPS[0])
        self.rules.add((48010, 12345))
        self.guard.check()
        self.assertEqual(self.guard.last_status, 'mapping_conflict')
        self.assertEqual(self.mutations(), [])

    def test_never_adopts_other_device(self):
        self.state(device='missing-tablet')
        self.guard.check()
        self.assertEqual(self.guard.last_status, 'waiting_device')
        self.assertEqual(len(self.calls), 1)

    def test_hdc_timeout_is_retried_by_worker(self):
        def timeout(args):
            self.guard.stop_event.set()
            raise subprocess.TimeoutExpired('hdc', 3)
        self.guard.runner = timeout
        self.guard._loop()
        self.assertEqual(self.guard.last_status, 'retrying')

    @unittest.skipUnless(sys.platform == 'win32', 'Windows mutex integration')
    def test_real_mutex_handle(self):
        with mode_lock() as held:
            self.assertTrue(held)
            result = []
            def contender():
                with mode_lock() as acquired:
                    result.append(acquired)
            thread = threading.Thread(target=contender)
            thread.start()
            thread.join(2)
            self.assertEqual(result, [False])


if __name__ == '__main__':
    unittest.main()

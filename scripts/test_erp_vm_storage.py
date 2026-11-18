"""Storage maintenance boundaries; synthetic inventories, no VM mutations."""
import copy
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import erp_vm_storage as storage


def fixture():
    containers = []
    for name, service, running in [('web', 'frontend', True), ('worker', 'queue-long', True),
                                    ('redis', 'redis-queue', True), ('db', 'db', True), ('old', 'configurator', False)]:
        containers.append({'id': name, 'name': name, 'image': 'sha256:' + name,
            'project': 'erp-baseline', 'service': service, 'config_files': str(storage.COMPOSE),
            'running': running, 'paused': False, 'restarting': False, 'dead': False,
            'restart_policy': {'Name': 'unless-stopped', 'MaximumRetryCount': 0}, 'mounts': []})
    return {'profile': 'erp', 'context': 'colima-erp', 'endpoint': storage.ENDPOINT,
        'cpu': 2, 'memory': 3 * 2**30, 'root_disk': 4 * 2**30, 'disk': 8 * 2**30, 'configured_disk': 8,
        'vm_type': 'vz', 'driver': 'macOS Virtualization.Framework', 'runtime': 'docker', 'disk_format': 'raw', 'disk_instance': 'colima-erp',
        'daemon_id': 'same-daemon', 'data_disk_identity': [1, 2], 'containers': containers, 'volumes': [{'Name': 'db-data', 'CreatedAt': 'original'}],
        'guest': {'device_bytes': 8 * 2**30, 'partition_bytes': 8 * 2**30 - 2**20, 'docker_total': 7 * 2**30}}


class StorageSafetyTests(unittest.TestCase):
    def test_unknown_profile_disk_resource_activity_and_launcher_mismatch_refuse(self):
        cases = [('profile', 'default'), ('context', 'default'), ('disk', 12 * 2**30),
                 ('cpu', 4), ('memory', 4 * 2**30), ('root_disk', 8 * 2**30), ('vm_type', 'qemu'),
                 ('driver', 'qemu'), ('configured_disk', 12)]
        for key, value in cases:
            state = fixture(); state[key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                storage.guard(state, 4 * 2**30, [], True)
        for free, jobs, launchers in [(2 * 2**30, [], True), (4 * 2**30, ['test active'], True), (4 * 2**30, [], False)]:
            with self.assertRaises(RuntimeError): storage.guard(fixture(), free, jobs, launchers)
        storage.guard(fixture(), 4 * 2**30, [], True)
        for key, value in [('project', 'foreign'), ('service', 'unknown-builder')]:
            state = fixture(); state['containers'][0][key] = value
            with self.assertRaises(RuntimeError): storage.guard(state, 4 * 2**30, [], True)

    def test_stop_order_keeps_databases_and_redis_until_application_stops(self):
        self.assertEqual(storage.ordered_groups(fixture()['containers']), [['web', 'worker'], ['redis'], ['db']])
        self.assertEqual(storage.ordered_groups(fixture()['containers'], starting=True), [['db'], ['redis'], ['web', 'worker']])

    def test_graceful_stop_never_schedules_a_forced_database_kill(self):
        calls = []
        with patch.object(storage, 'run', side_effect=lambda args, **kwargs: calls.append((args, kwargs))):
            storage.container_action('stop', ['db'])
        self.assertEqual(calls, [(['docker', '--context', 'colima-erp', 'stop', '--time', '-1', 'db'], {'timeout': 180})])

    def test_changed_container_image_restart_policy_or_volume_identity_refuses_restore(self):
        for change in ['image', 'restart_policy', 'volume', 'data_disk_identity']:
            before, after = fixture(), fixture()
            if change == 'volume': after['volumes'][0]['CreatedAt'] = 'replacement'
            elif change == 'data_disk_identity': after[change] = [1, 99]
            else: after['containers'][0][change] = 'replacement'
            with self.subTest(change=change), self.assertRaises(RuntimeError): storage.same_identities(before, after)

    def test_reconcile_stops_auto_started_old_container_and_restores_only_original_ids(self):
        before, now = fixture(), fixture()
        for item in now['containers']: item['running'] = item['id'] == 'old'
        actions = []
        storage.restore(before, now, lambda verb, ids: actions.append((verb, ids)))
        self.assertEqual(actions, [('stop', ['old']), ('start', ['db']), ('start', ['redis']), ('start', ['web', 'worker'])])

    def test_in_progress_build_or_test_commands_are_detected_but_service_workers_are_allowed(self):
        self.assertTrue(storage.busy_command('make -j1 check'))
        self.assertTrue(storage.busy_command('bench --site native-test.localhost run-tests --app erp_extensions'))
        self.assertTrue(storage.busy_command('flutter test --concurrency=1'))
        self.assertTrue(storage.busy_command('python3 scripts/test_security_config.py'))
        self.assertTrue(storage.busy_command('docker --context colima-erp exec backend python3 -'))
        self.assertFalse(storage.busy_command('bench worker --queue short,default'))
        self.assertFalse(storage.busy_command('mariadbd --user=mysql'))

    def test_execute_resource_refusal_never_reaches_service_or_vm_mutations(self):
        with patch.object(storage.sys, 'argv', ['erp-vm-storage', '--execute']), \
                patch.object(storage, 'inventory', return_value=fixture()), \
                patch.object(storage, 'activities', return_value=[]), \
                patch.object(storage, 'launchers_ready', return_value=True), \
                patch.object(storage.shutil, 'disk_usage', return_value=SimpleNamespace(free=2*2**30)), \
                patch.object(storage, 'maintain', side_effect=AssertionError('Must not mutate services')):
            with self.assertRaisesRegex(RuntimeError, '2.4 GiB'): storage.main()

    def test_failed_vm_start_restores_original_services_without_shrinking(self):
        before = fixture()
        stopped = copy.deepcopy(before)
        for item in stopped['containers']: item['running'] = False
        recovered = copy.deepcopy(before); recovered['disk'] = 12*2**30
        events, report = [], {}
        calls = iter([stopped, RuntimeError('VM stopped'), stopped, recovered])
        def inventory():
            value = next(calls)
            if isinstance(value, Exception): raise value
            return value
        def start(size):
            events.append(('vm-start', size))
            if sum(event[0] == 'vm-start' for event in events) == 1: raise RuntimeError('start failed')
        with patch.object(storage, 'inventory', side_effect=inventory), \
                patch.object(storage, 'container_action', side_effect=lambda verb, ids: events.append((verb, ids))), \
                patch.object(storage, 'run', side_effect=lambda args, **kw: events.append(('command', args))), \
                patch.object(storage, 'start_vm', side_effect=start), \
                patch.object(storage, 'DISK', SimpleNamespace(stat=lambda: SimpleNamespace(st_size=12*2**30))):
            with self.assertRaisesRegex(RuntimeError, 'start failed'): storage.maintain(before, report, lambda value: None)
        self.assertEqual([event for event in events if event[0] in {'stop', 'start', 'vm-start'}], [
            ('stop', ['web', 'worker']), ('stop', ['redis']), ('stop', ['db']), ('vm-start', 12), ('vm-start', 12),
            ('start', ['db']), ('start', ['redis']), ('start', ['web', 'worker'])])
        self.assertTrue(report['original_running_states_restored'])
        self.assertEqual(report['status'], 'failed')

    def test_disk_file_growth_without_guest_filesystem_growth_never_counts_as_success(self):
        before, after = fixture(), fixture()
        after.update(disk=12*2**30, configured_disk=12)
        after['guest'].update(device_bytes=12*2**30, partition_bytes=12*2**30-2**20, docker_total=12*2**30-2**28)
        storage.validate_after(before, after)
        for change in ['filesystem', 'running', 'paused']:
            broken = copy.deepcopy(after)
            if change == 'filesystem': broken['guest']['docker_total'] = 7*2**30
            elif change == 'running': broken['containers'][-1]['running'] = True
            else: broken['containers'][0]['paused'] = True
            with self.subTest(change=change), self.assertRaises(RuntimeError): storage.validate_after(before, broken)


if __name__ == '__main__': unittest.main()

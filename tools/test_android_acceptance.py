"""Host safety gates; these tests need neither ADB nor a backend."""
import unittest
from run_android_acceptance import check_package, check_reverse_available, validate_phase


class AcceptanceEvidenceTest(unittest.TestCase):
    def test_regular_apk_is_rejected(self):
        with self.assertRaises(RuntimeError):
            check_package("package: name='app.logos.bible' versionCode='1'")
        check_package("package: name='app.logos.bible.integration' versionCode='1'")

    def test_existing_backend_tunnel_is_left_untouched(self):
        with self.assertRaises(RuntimeError):
            check_reverse_available('host-1 tcp:18081 tcp:8080\n')
        check_reverse_available('host-1 tcp:8080 tcp:8080\n')

    def test_warm_restart_or_old_report_cannot_pass_as_cold_start(self):
        valid = {'acceptance': {'runId': 'run', 'phase': 'offline-reopen', 'pid': 42}}
        self.assertEqual(validate_phase(valid, 'run', 'offline-reopen', {40, 41}), 42)
        for data in ({}, valid, {'acceptance': {'runId': 'previous', 'phase': 'offline-reopen', 'pid': 43}}):
            with self.assertRaises(RuntimeError):
                validate_phase(data, 'run', 'offline-reopen', {42})


if __name__ == '__main__':
    unittest.main()

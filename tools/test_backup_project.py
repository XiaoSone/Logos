"""Recovery/authentication and Windows temporary-data cleanup checks."""
import os
from pathlib import Path
import stat
import tempfile
import unittest
from cryptography.exceptions import InvalidTag
from backup_project import decrypt_file, dpapi, encrypt_file, remove_stage


class BackupRecoveryTest(unittest.TestCase):
    def test_readonly_git_files_are_cleaned(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            stage = output / '.staging'
            pack = stage / 'restored/.git/objects/pack/fixture.idx'
            pack.parent.mkdir(parents=True)
            pack.write_bytes(b'git verification fixture')
            pack.chmod(stat.S_IREAD)
            remove_stage(stage, output)
            self.assertFalse(stage.exists())

    def test_cleanup_rejects_an_unowned_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            unrelated = output / 'keep'
            unrelated.mkdir()
            marker = unrelated / 'keep.txt'
            marker.write_text('must survive', encoding='utf-8')
            with self.assertRaises(RuntimeError):
                remove_stage(unrelated, output)
            self.assertTrue(marker.exists())

    @unittest.skipUnless(os.name == 'nt', 'Windows DPAPI')
    def test_protected_key_recovers_payload_and_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, encrypted, restored = (root / name for name in ('source', 'encrypted', 'restored'))
            source.write_bytes(os.urandom(1024 * 1024 + 7))
            key = os.urandom(32)
            recovered_key = dpapi(dpapi(key), decrypt=True)
            encrypt_file(source, encrypted, key)
            decrypt_file(encrypted, restored, recovered_key)
            self.assertEqual(source.read_bytes(), restored.read_bytes())
            damaged = bytearray(encrypted.read_bytes())
            damaged[-1] ^= 1
            encrypted.write_bytes(damaged)
            with self.assertRaises(InvalidTag):
                decrypt_file(encrypted, root / 'rejected', recovered_key)


if __name__ == '__main__':
    unittest.main()

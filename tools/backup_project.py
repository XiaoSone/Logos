"""Independent committed-source backup with verified Windows-protected private data.

Requires Python cryptography and PG18 tools. DPAPI ties private recovery to the
current Windows user/machine; copy to another disk separately for disaster recovery.
"""
import argparse
import ctypes
from ctypes import wintypes
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid
import zipfile
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

ROOT = Path(__file__).resolve().parents[1]
HEADER = b'LOGOS-BACKUP-1\0'


class Blob(ctypes.Structure):
    _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_ubyte))]


def dpapi(data, *, decrypt=False):
    if os.name != 'nt':
        raise RuntimeError('Private backups require Windows DPAPI')
    buffer = ctypes.create_string_buffer(data)
    source = Blob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    output = Blob()
    library = ctypes.WinDLL('crypt32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    operation = library.CryptUnprotectData if decrypt else library.CryptProtectData
    operation.argtypes = [ctypes.POINTER(Blob), ctypes.c_void_p, ctypes.c_void_p,
                          ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(Blob)]
    operation.restype = wintypes.BOOL
    if not operation(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output)):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return ctypes.string_at(output.data, output.size)
    finally:
        kernel.LocalFree(output.data)


def encrypt_file(source, target, key):
    nonce = os.urandom(12)
    cipher = Cipher(algorithms.AES(key), modes.GCM(nonce)).encryptor()
    cipher.authenticate_additional_data(HEADER + nonce)
    with source.open('rb') as original, target.open('xb') as encrypted:
        encrypted.write(HEADER + nonce)
        while block := original.read(1024 * 1024):
            encrypted.write(cipher.update(block))
        encrypted.write(cipher.finalize())
        encrypted.write(cipher.tag)


def decrypt_file(source, target, key):
    with source.open('rb') as encrypted, target.open('xb') as original:
        if encrypted.read(len(HEADER)) != HEADER:
            raise RuntimeError('Unrecognized private backup format')
        nonce = encrypted.read(12)
        encrypted.seek(-16, 2)
        tag = encrypted.read(16)
        remaining = encrypted.tell() - 16 - len(HEADER) - 12
        encrypted.seek(len(HEADER) + 12)
        cipher = Cipher(algorithms.AES(key), modes.GCM(nonce, tag)).decryptor()
        cipher.authenticate_additional_data(HEADER + nonce)
        while remaining:
            block = encrypted.read(min(1024 * 1024, remaining))
            if not block:
                raise RuntimeError('Truncated private backup')
            original.write(cipher.update(block))
            remaining -= len(block)
        original.write(cipher.finalize())


def command(args, *, cwd=ROOT):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{Path(str(args[0])).name} failed (exit {result.returncode}); no secrets printed')
    return result.stdout.decode('utf-8').strip()


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def remove_stage(stage, output):
    # The only recursive deletion is a checked, run-created staging directory.
    resolved = stage.resolve()
    if resolved.parent != output.resolve() or resolved.name != '.staging':
        raise RuntimeError('Unsafe staging cleanup path')
    if resolved.exists():
        shutil.rmtree(resolved)


def make_backup(output, pg_bin):
    output = output.resolve()
    if output.is_relative_to(ROOT):
        raise RuntimeError('Choose an independent directory outside the workspace')
    if command(['git', 'status', '--porcelain']):
        raise RuntimeError('Commit the source baseline before making this backup')
    commit = command(['git', 'rev-parse', 'HEAD'])
    output.mkdir(parents=True, exist_ok=False)
    stage = output / '.staging'
    stage.mkdir()
    pg_base = ['-h', '127.0.0.1', '-p', '55432', '-U', 'logos']
    restore_db = None
    try:
        command(['git', 'archive', '--format=zip', f'--output={output / "source.zip"}', commit])
        command(['git', 'bundle', 'create', output / 'history.bundle', '--all'])
        command(['git', 'bundle', 'verify', output / 'history.bundle'])
        with zipfile.ZipFile(output / 'source.zip') as archive:
            if archive.testzip() is not None:
                raise RuntimeError('Source ZIP integrity failure')
        command(['git', 'clone', '--quiet', output / 'history.bundle', stage / 'restored-source'])
        if command(['git', 'rev-parse', 'HEAD'], cwd=stage / 'restored-source') != commit:
            raise RuntimeError('Git bundle restore does not match baseline')

        artifacts = output / 'artifacts'
        artifacts.mkdir()
        for apk in (ROOT / 'dist').glob('*.apk'):
            shutil.copyfile(apk, artifacts / apk.name)
            if digest(apk) != digest(artifacts / apk.name):
                raise RuntimeError('APK backup checksum mismatch')
        if not any(artifacts.glob('*.apk')):
            raise RuntimeError('No distribution APK found')

        dump = stage / 'logos.dump'
        command([pg_bin / 'pg_dump.exe', *pg_base, '-d', 'logos', '-Fc', '--no-owner',
                 '--no-privileges', '-f', dump])
        private = stage / 'private.zip'
        secret_sources = [ROOT / '.tools/bible-key.txt', ROOT / '.tools/jwt-secret.txt']
        if not all(path.is_file() for path in secret_sources):
            raise RuntimeError('Required local runtime keys missing')
        with zipfile.ZipFile(private, 'x', zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
            archive.write(dump, 'database/logos.dump')
            for path in secret_sources:
                archive.write(path, path.relative_to(ROOT).as_posix())
            if (ROOT / '.env').is_file():
                archive.write(ROOT / '.env', '.env')
            signing = Path(os.environ['USERPROFILE']) / '.android/debug.keystore'
            if signing.is_file():
                archive.write(signing, 'signing/debug.keystore')
            for path in (ROOT / '.tools/device-backups').rglob('*'):
                if path.is_file():
                    archive.write(path, path.relative_to(ROOT).as_posix())
        key = os.urandom(32)
        (output / 'private-key.dpapi').write_bytes(dpapi(key))
        encrypt_file(private, output / 'private.aes256gcm', key)

        # Verify decryption with the protected key, then restore the actual
        # decrypted DB archive into a new, explicitly owned scratch database.
        recovered = stage / 'recovered.zip'
        decrypt_file(output / 'private.aes256gcm', recovered,
                     dpapi((output / 'private-key.dpapi').read_bytes(), decrypt=True))
        with zipfile.ZipFile(recovered) as archive:
            if archive.testzip() is not None:
                raise RuntimeError('Private ZIP integrity failure')
            for path in secret_sources:
                if archive.read(path.relative_to(ROOT).as_posix()) != path.read_bytes():
                    raise RuntimeError('Runtime key round-trip mismatch')
            recovered_dump = stage / 'recovered.dump'
            with archive.open('database/logos.dump') as source, recovered_dump.open('wb') as target:
                shutil.copyfileobj(source, target)
        restore_db = 'logos_restore_' + uuid.uuid4().hex[:12]
        psql = [pg_bin / 'psql.exe', '-X', *pg_base, '-v', 'ON_ERROR_STOP=1']
        command([*psql, '-d', 'postgres', '-c', f'CREATE DATABASE {restore_db}'])
        command([pg_bin / 'pg_restore.exe', *pg_base, '-d', restore_db, '--exit-on-error',
                 '--no-owner', '--no-privileges', recovered_dump])
        counts = command([*psql, '-d', restore_db, '-At', '-c',
                          'SELECT (SELECT count(*) FROM bible_book),'
                          '(SELECT count(*) FROM bible_verse)'])
        if counts != '66|31092':
            raise RuntimeError('Restored database canon counts do not match')
        command([*psql, '-d', 'postgres', '-c', f'DROP DATABASE {restore_db} WITH (FORCE)'])
        restore_db = None
        manifest = {
            'createdAt': dt.datetime.now().astimezone().isoformat(),
            'commit': commit, 'branch': command(['git', 'branch', '--show-current']),
            'sourceZipVerified': True, 'gitBundleCloneVerified': True,
            'privateDecryptionVerified': True, 'postgresRestoreVerified': True,
            'restoredBooks': 66, 'restoredVerseAddresses': 31092,
            'privateRecovery': 'Windows DPAPI: same Windows user/machine required',
            'exclusions': ['SDK/JDK/build caches', 'original APK/decompiled assets',
                           'uncommitted working-tree files', 'live Android device not queried'],
        }
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        (output / 'RESTORE.txt').write_text(
            'Logos independent backup\n\n'
            f'Commit: {commit}\n'
            'git clone history.bundle Logos-restored\n'
            'source.zip: committed source only; artifacts/: existing distribution APKs.\n'
            'Private archive contains the PG18/55432 logos DB snapshot, matching Bible/JWT keys,\n'
            'optional .env/debug signing key, and existing local phone-data backups.\n'
            'It does not fetch current phone data. SDKs/build caches are excluded.\n\n'
            'Verify SHA256SUMS.json before recovery. On the SAME Windows user/machine:\n'
            'python tools/backup_project.py --extract-private BACKUP_DIR --to NEW_PRIVATE_DIR\n'
            'The extracted data is private. Install PG18 and restore database/logos.dump\n'
            'into a NEW database with pg_restore --no-owner --no-privileges.\n'
            'Copy runtime keys only into ignored .tools paths. Never commit extracted secrets.\n'
            'Android Keystore keys cannot be recovered from copied app files alone.\n'
            'Do not downgrade an installed v2 database to the pre-v2 APK.\n\n'
            'A separate directory on the same disk is not an offsite/disaster-recovery copy.\n'
            'DPAPI is not a portable secret-escrow solution for a replacement Windows account.\n',
            encoding='utf-8',
        )
        paths = [path for path in output.rglob('*') if path.is_file() and not path.is_relative_to(stage)]
        checksums = {path.relative_to(output).as_posix(): digest(path) for path in sorted(paths)}
        (output / 'SHA256SUMS.json').write_text(json.dumps(checksums, indent=2), encoding='utf-8')
        print(json.dumps({'backup': str(output), 'commit': commit,
                          'verifiedFiles': len(checksums), 'postgresRestoreVerified': True}))
    finally:
        if restore_db:
            command([pg_bin / 'psql.exe', '-X', *pg_base, '-d', 'postgres', '-v',
                     'ON_ERROR_STOP=1', '-c', f'DROP DATABASE IF EXISTS {restore_db} WITH (FORCE)'])
        remove_stage(stage, output)


def extract_private(backup, destination):
    backup = backup.resolve()
    checksums = json.loads((backup / 'SHA256SUMS.json').read_text(encoding='utf-8'))
    for name in ('private-key.dpapi', 'private.aes256gcm'):
        if digest(backup / name) != checksums[name]:
            raise RuntimeError('Private backup checksum mismatch')
    destination.mkdir(parents=True, exist_ok=False)
    archive_file = destination / 'private.zip'
    try:
        decrypt_file(backup / 'private.aes256gcm', archive_file,
                     dpapi((backup / 'private-key.dpapi').read_bytes(), decrypt=True))
        with zipfile.ZipFile(archive_file) as archive:
            for item in archive.infolist():
                if not (destination / item.filename).resolve().is_relative_to(destination.resolve()):
                    raise RuntimeError('Invalid private archive path')
            archive.extractall(destination)
    finally:
        archive_file.unlink(missing_ok=True)
    print('Private backup extracted to the explicitly selected directory.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--output', type=Path)
    mode.add_argument('--extract-private', type=Path)
    parser.add_argument('--to', type=Path)
    parser.add_argument('--pg-bin', type=Path, default=Path('D:/PostgreSQL/18/bin'))
    args = parser.parse_args()
    if args.extract_private:
        if args.to is None:
            parser.error('--to is required for private extraction')
        extract_private(args.extract_private, args.to)
    else:
        make_backup(args.output, args.pg_bin)


if __name__ == '__main__':
    main()

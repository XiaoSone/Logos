"""Build/run Android acceptance in an isolated app + disposable PG database.

No Wi-Fi/airplane-mode changes: only this run's localhost ADB reverse is removed.
The Flutter VM-service forward remains available while the backend is unreachable.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'apps/logos'
PACKAGE = 'app.logos.bible.integration'
DEVICE_PORT = 18081
PHASES = ('core', 'seed', 'offline-write', 'offline-reopen', 'reconnect')


def validate_phase(data, run_id, phase, previous_pids):
    report = (data or {}).get('acceptance', {})
    if report.get('runId') != run_id or report.get('phase') != phase:
        raise RuntimeError('Missing/mismatched phase evidence; not a passing run')
    pid = report.get('pid')
    if not isinstance(pid, int) or pid <= 0 or pid in previous_pids:
        raise RuntimeError('A new Android process was not proven for this phase')
    return pid


def check_package(badging):
    if f"package: name='{PACKAGE}'" not in badging.splitlines()[0]:
        raise RuntimeError('Refusing to install a non-isolated APK')


def check_reverse_available(listing):
    if any(f'tcp:{DEVICE_PORT}' == part for line in listing.splitlines()
           for part in line.split()[1:2]):
        raise RuntimeError(f'ADB reverse {DEVICE_PORT} already exists; left unchanged')


class Run:
    def __init__(self, args):
        self.args = args
        self.run_id = uuid.uuid4().hex[:16]
        stamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S')
        self.output = ROOT / 'analysis/android-acceptance' / f'{stamp}-{self.run_id}'
        self.output.mkdir(parents=True)
        self.env = os.environ.copy()
        self.env.update({
            'FLUTTER_STORAGE_BASE_URL': 'https://storage.flutter-io.cn',
            'PUB_HOSTED_URL': 'https://pub.flutter-io.cn',
            'GRADLE_USER_HOME': str(ROOT / '.tools/gradle'),
            'TEMP': str(ROOT / '.tools/tmp'), 'TMP': str(ROOT / '.tools/tmp'),
        })
        (ROOT / '.tools/tmp').mkdir(exist_ok=True)
        jdk = next((ROOT / '.tools/jdk21').glob('*/bin/java.exe'))
        self.java = jdk
        self.env['JAVA_HOME'] = str(jdk.parent.parent)
        self.env['PATH'] = str(jdk.parent) + os.pathsep + self.env['PATH']
        self.flutter = ROOT / '.tools/flutter/bin/flutter.bat'
        self.adb = ROOT / '.tools/android-sdk/platform-tools/adb.exe'
        self.pg = Path(args.pg_bin)
        self.backend = None
        self.database = None
        self.reverse_owned = False
        self.results = []

    def command(self, command, *, cwd=ROOT, log=None, input=None, check=True, timeout=600):
        command = [str(part) for part in command]
        command[0] = shutil.which(command[0], path=self.env['PATH']) or command[0]
        if log:
            with (self.output / log).open('wb') as stream:
                result = subprocess.run(command, cwd=cwd, env=self.env, input=input,
                                        stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        else:
            result = subprocess.run(command, cwd=cwd, env=self.env, input=input,
                                    capture_output=True, timeout=timeout)
        if check and result.returncode:
            raise RuntimeError(f'{Path(command[0]).name} failed; see {log or "preflight"}')
        return result

    def adb_call(self, *args, **kwargs):
        timeout = kwargs.pop('timeout', 30)
        return self.command([self.adb, '-s', self.args.device, *args], timeout=timeout, **kwargs)

    def build(self):
        print('Building isolated acceptance APK...', flush=True)
        self.command([
            self.flutter, '--no-version-check', 'build', 'apk', '--debug', '--no-pub',
            '--target-platform', self.args.target_platform,
            '--target', 'integration_test/core_flow_test.dart',
            '--dart-define=LOGOS_ANDROID_ACCEPTANCE=true',
            f'--dart-define=API_URL=http://127.0.0.1:{DEVICE_PORT}/graphql',
        ], cwd=APP, log='build.log', timeout=900)
        self.apk = self.output / 'logos-acceptance.apk'
        shutil.copyfile(APP / 'build/app/outputs/flutter-apk/app-debug.apk', self.apk)
        aapt = sorted((ROOT / '.tools/android-sdk/build-tools').glob('*/aapt.exe'))[-1]
        badging = self.command([aapt, 'dump', 'badging', self.apk]).stdout.decode('utf-8')
        check_package(badging)

    def start_backend(self):
        # Never use, drop or migrate the user's logos DB. All lifecycle test data
        # and Bible device registrations are confined to a newly generated DB.
        self.env['JWT_SECRET'] = secrets.token_urlsafe(48)
        self.command(['mvn', '-f', 'backend/pom.xml', '-DskipTests', 'package'],
                     log='backend-build.log', timeout=600)
        name = 'logos_android_' + self.run_id
        self.psql('SELECT 1')
        self.psql(f'CREATE DATABASE {name}')
        self.database = name
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            self.backend_port = sock.getsockname()[1]
        self.env.update({
            'DATABASE_URL': f'jdbc:postgresql://127.0.0.1:55432/{name}',
            'DATABASE_USER': 'logos', 'DATABASE_PASSWORD': '',
            'BIBLE_PATH': str(ROOT / 'data/bible.json'),
            'BIBLE_KEY_FILE': str(ROOT / '.tools/bible-key.txt'),
            'SERVER_ADDRESS': '127.0.0.1', 'PORT': str(self.backend_port),
        })
        self.backend_log = (self.output / 'backend.log').open('wb')
        options = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
        self.backend = subprocess.Popen([
            str(self.java), '-Xmx384m', '-jar',
            str(ROOT / 'backend/target/logos-server-0.1.0.jar'),
            '--spring.profiles.active=dev',
        ], cwd=ROOT / 'backend', env=self.env, stdout=self.backend_log,
            stderr=subprocess.STDOUT, **options)
        deadline = time.monotonic() + 100
        while time.monotonic() < deadline:
            if self.backend.poll() is not None:
                raise RuntimeError('Disposable backend exited; see backend.log')
            request = urllib.request.Request(
                f'http://127.0.0.1:{self.backend_port}/graphql',
                data=b'{"query":"{loginAvailable}"}',
                headers={'Content-Type': 'application/json'},
            )
            try:
                with urllib.request.urlopen(request, timeout=2) as response:
                    if json.load(response).get('data', {}).get('loginAvailable') is True:
                        return
            except (OSError, ValueError):
                pass
            time.sleep(1)
        raise RuntimeError('Disposable backend startup timed out')

    def psql(self, sql):
        self.command([self.pg / 'psql.exe', '-X', '-h', '127.0.0.1', '-p', '55432',
                      '-U', 'logos', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', sql])

    def execute(self):
        if not self.args.build_only:
            self.adb_call('get-state')
            check_reverse_available(self.adb_call('reverse', '--list').stdout.decode())
        self.build()
        if self.args.build_only:
            return
        self.start_backend()
        installed = self.adb_call('shell', 'pm', 'list', 'packages', PACKAGE).stdout.decode()
        if f'package:{PACKAGE}' in installed.splitlines():
            self.adb_call('uninstall', PACKAGE)  # This dedicated test package only.
        self.adb_call('install', str(self.apk), timeout=180)
        phone_a = '199' + f'{secrets.randbelow(100000000):08d}'
        phone_b = phone_a
        while phone_b == phone_a:
            phone_b = '199' + f'{secrets.randbelow(100000000):08d}'
        previous_pids = set()
        for phase in PHASES:
            print(f'Running {phase} in a new Android process...', flush=True)
            self.adb_call('shell', 'am', 'force-stop', PACKAGE)
            alive = self.adb_call('shell', 'pidof', PACKAGE, check=False)
            if alive.stdout.strip():
                raise RuntimeError('force-stop did not terminate the test process')
            if phase == 'offline-write':
                self.adb_call('reverse', '--remove', f'tcp:{DEVICE_PORT}')
                self.reverse_owned = False
            elif phase in ('core', 'reconnect'):
                self.adb_call('reverse', f'tcp:{DEVICE_PORT}', f'tcp:{self.backend_port}')
                self.reverse_owned = True
            config = json.dumps({'phase': phase, 'runId': self.run_id,
                                 'phoneA': phone_a, 'phoneB': phone_b}).encode()
            self.adb_call('shell', 'run-as', PACKAGE, 'mkdir', '-p', 'files')
            self.adb_call('shell', 'run-as', PACKAGE, 'tee', 'files/logos-acceptance.json', input=config)
            report_file = self.output / f'{phase}.json'
            self.env['LOGOS_ACCEPTANCE_OUTPUT'] = str(report_file)
            self.command([
                self.flutter, '--no-version-check', 'drive', '--no-pub',
                '--driver', 'test_driver/integration_test.dart',
                '--target', 'integration_test/core_flow_test.dart',
                '--use-application-binary', self.apk, '-d', self.args.device,
            ], cwd=APP, log=f'{phase}.log', timeout=420)
            pid = validate_phase(json.loads(report_file.read_text(encoding='utf-8')),
                                 self.run_id, phase, previous_pids)
            previous_pids.add(pid)
            self.results.append({'phase': phase, 'pid': pid, 'passed': True,
                                 'backendReachable': not phase.startswith('offline-')})

    def cleanup(self):
        errors = []
        if self.reverse_owned:
            try:
                self.adb_call('reverse', '--remove', f'tcp:{DEVICE_PORT}')
            except Exception:
                errors.append('Could not remove this run\'s ADB reverse')
        if self.backend is not None:
            if self.backend.poll() is None:
                self.backend.terminate()
                try:
                    self.backend.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    self.backend.kill()
                    self.backend.wait(timeout=10)
            self.backend_log.close()
        if self.database:
            try:
                self.psql(f'DROP DATABASE {self.database} WITH (FORCE)')
            except Exception:
                errors.append(f'Could not remove disposable DB {self.database}')
        return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', help='Explicit ADB serial of a dedicated test device')
    parser.add_argument('--build-only', action='store_true', help='Compile/verify test package; no device/DB writes')
    parser.add_argument('--target-platform', choices=['android-arm64', 'android-x64'], default='android-arm64')
    parser.add_argument('--pg-bin', default='D:/PostgreSQL/18/bin')
    args = parser.parse_args()
    if not args.build_only and not args.device:
        parser.error('--device is required unless --build-only is used')
    run = Run(args)
    error = None
    try:
        run.execute()
    except Exception as failure:
        error = str(failure)
    finally:
        cleanup_errors = run.cleanup()
        result = {'runId': run.run_id, 'buildOnly': args.build_only,
                  'package': PACKAGE, 'phases': run.results, 'error': error,
                  'cleanupErrors': cleanup_errors,
                  'passed': not args.build_only and len(run.results) == len(PHASES)
                            and error is None and not cleanup_errors}
        (run.output / 'summary.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(run.output, flush=True)
    if error or cleanup_errors:
        raise SystemExit(error or '; '.join(cleanup_errors))


if __name__ == '__main__':
    main()

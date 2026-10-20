"""Preload upstream, hash-pinned SQLite hook binaries without changing package code."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import requests

ROOT=Path(__file__).resolve().parents[1]
config=json.loads((ROOT/'apps/logos/.dart_tool/package_config.json').read_text('utf-8'))
from urllib.parse import unquote,urlparse
uri=next(p['rootUri'] for p in config['packages'] if p['name']=='sqlite3')
package=Path(unquote(urlparse(uri).path).lstrip('/')) if uri.startswith('file:') else (ROOT/'apps/logos/.dart_tool'/uri).resolve()
version=json.loads((ROOT/'apps/logos/.dart_tool/package_config.json').read_text('utf-8')) # package version comes from pubspec below
import yaml
version=yaml.safe_load((package/'pubspec.yaml').read_text('utf-8'))['version']
hashes=dict(re.findall(r"'([^']+)':\s*'([a-f0-9]{64})'",(package/'lib/src/hook/asset_hashes.dart').read_text('utf-8')))
def fetch(name):
    digest=hashes[name]
    target=ROOT/'apps/logos/.dart_tool/hooks_runner/shared/sqlite3/build'/f'download-{digest[:8]}'/('sqlite3.dll' if name.endswith('.dll') else 'libsqlite3.so')
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()==digest:
        return
    response=requests.get(f'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-{version}/{name}',timeout=90)
    response.raise_for_status()
    assert hashlib.sha256(response.content).hexdigest()==digest,name
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(response.content)
    print(name,digest,flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    list(pool.map(fetch,['sqlite3.x64.windows.dll','libsqlite3.arm64.android.so','libsqlite3.x64.android.so']))

"""Populate Dart's hosted cache from a lockfile when Dart HTTP stalls on Windows."""
import concurrent.futures
import hashlib
import io
import os
from pathlib import Path
import sys
import tarfile
import requests
import yaml

cache = Path(os.environ.get('LOCALAPPDATA',Path.home()))/'Pub'/'Cache'
lock = yaml.safe_load(Path(sys.argv[1]).read_text(encoding='utf-8'))
def fetch(item):
    name, spec = item
    if spec['source'] != 'hosted':
        return
    version = spec['version']
    target = cache/'hosted'/'pub.dev'/f'{name}-{version}'
    if (target/'pubspec.yaml').exists():
        return
    url = f'https://pub.dev/api/archives/{name}-{version}.tar.gz'
    response = requests.get(url,timeout=90)
    response.raise_for_status()
    content = response.content
    digest=hashlib.sha256(content).hexdigest()
    if spec['description'].get('sha256') and digest != spec['description']['sha256']:
        raise ValueError('Checksum mismatch: '+name)
    target.mkdir(parents=True,exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(content),mode='r:gz') as archive:
        archive.extractall(target,filter='data')
    hashes=cache/'hosted-hashes'/'pub.dev'
    hashes.mkdir(parents=True,exist_ok=True)
    (hashes/f'{name}-{version}.sha256').write_text(digest)
    print(name,version,flush=True)

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    list(pool.map(fetch,lock['packages'].items()))

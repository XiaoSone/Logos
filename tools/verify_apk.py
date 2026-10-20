"""Check the actual Logos package; never print the development master key."""
import base64
import hashlib
import json
import sys
import zipfile
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    apk = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'dist/logos-0.1.0-debug.apk'
    master = (root / '.tools/bible-key.txt').read_text(encoding='utf-8').strip().encode()
    raw_master = base64.b64decode(master, validate=True)
    assert len(raw_master) == 32
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        bible_name = 'assets/flutter_assets/assets/bible.bin'
        assert bible_name in names, 'Encrypted Bible asset missing'
        assert archive.read(bible_name) == (root / 'data/bible.bin').read_bytes()
        assert not any(n.endswith('/bible.json') or n.endswith('/bible-key.txt') for n in names)
        for name in names:
            if name.endswith('/'):
                continue
            content = archive.read(name)
            assert master not in content and raw_master not in content, f'Master key leaked into {name}'
        native = sorted({n.split('/')[1] for n in names if n.startswith('lib/')})
        assert native == ['arm64-v8a', 'x86_64'], native
    with apk.open('rb') as apk_file:
        digest = hashlib.file_digest(apk_file, 'sha256').hexdigest()
    report = {
        'file': apk.name,
        'bytes': apk.stat().st_size,
        'sha256': digest,
        'abis': native,
        'checks': ['ciphertext matches data snapshot', 'no plaintext Bible JSON',
                   'no master key file, Base64 key or raw key in ZIP entries'],
    }
    output = root / 'analysis/logos-apk-verification.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

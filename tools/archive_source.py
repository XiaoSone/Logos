"""Create a local handoff snapshot, excluding ignored caches and secrets."""
import argparse
import hashlib
import subprocess
import zipfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--include-apk', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    paths = subprocess.run(
        ['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=root,
        check=True, capture_output=True,
    ).stdout.decode('utf-8').split('\0')
    paths = sorted(set(p for p in paths if p))
    if args.include_apk:
        paths.append('dist/logos-0.1.0-debug.apk')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with zipfile.ZipFile(args.output, 'x', compression=zipfile.ZIP_DEFLATED,
                         compresslevel=1) as archive:
        for relative in paths:
            path = (root / relative).resolve()
            assert path.is_relative_to(root)
            assert not relative.startswith(('.tools/', '.git/', 'analysis/raw/'))
            assert path.name not in ('.env', 'bible-key.txt')
            if path.is_file():
                archive.write(path, relative, compress_type=(
                    zipfile.ZIP_STORED if path.suffix == '.apk' else zipfile.ZIP_DEFLATED))
                count += 1
    with args.output.open('rb') as snapshot:
        digest = hashlib.file_digest(snapshot, 'sha256').hexdigest()
    print(f'{count} files; {args.output.stat().st_size} bytes; SHA-256 {digest}')
    print(args.output)


if __name__ == '__main__':
    main()

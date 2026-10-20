"""Reproducible APK evidence inventory. Never executes the inspected application."""
import hashlib
import json
import re
import zipfile
from collections import Counter
from pathlib import Path
from loguru import logger

logger.remove()
from androguard.core.apk import APK
from androguard.core.axml import AXMLPrinter
from androguard.core.dex import DEX

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'analysis' / 'raw'
OUT.mkdir(parents=True, exist_ok=True)
apk_path = ROOT / 'wdbible_website_7_6_1.apk'

def write(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def main():
    apk = APK(str(apk_path))
    manifest = apk.get_android_manifest_xml()
    from lxml import etree
    (OUT / 'AndroidManifest.xml').write_bytes(etree.tostring(manifest, pretty_print=True, encoding='utf-8'))
    certs = apk.get_certificates()
    write('package.json', dict(sha256=hashlib.file_digest(apk_path.open('rb'), 'sha256').hexdigest(),
        size=apk_path.stat().st_size, package=apk.get_package(), label=apk.get_app_name(),
        version=apk.get_androidversion_name(), versionCode=apk.get_androidversion_code(),
        minSdk=apk.get_min_sdk_version(), targetSdk=apk.get_target_sdk_version(),
        activities=apk.get_activities(), services=apk.get_services(), receivers=apk.get_receivers(),
        providers=apk.get_providers(), permissions=apk.get_permissions(), mainActivity=apk.get_main_activity(),
        signatureSchemes={'v1':apk.is_signed_v1(),'v2':apk.is_signed_v2(),'v3':apk.is_signed_v3()},
        certificateSha256=[hashlib.sha256(c.dump()).hexdigest() for c in certs]))
    with zipfile.ZipFile(apk_path) as archive:
        entries = [dict(name=i.filename, size=i.file_size, compressed=i.compress_size) for i in archive.infolist()]
        write('archive.json', entries)
        classes, strings = [], set()
        for entry in entries:
            name = entry['name']
            if re.fullmatch(r'classes\d*\.dex', name):
                dex = DEX(archive.read(name))
                classes.extend({'dex':name,'name':c.get_name(),'super':c.get_superclassname(),
                    'methods':[m.get_name()+m.get_descriptor() for m in c.get_methods()]} for c in dex.get_classes())
                strings.update(str(s) for s in dex.get_strings())
            if name.startswith('res/layout') and name.endswith('.xml'):
                target = OUT / 'layouts' / name.replace('/', '__')
                try:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(AXMLPrinter(archive.read(name)).get_xml())
                except Exception as exc:
                    print('layout decode:',name,type(exc).__name__)
            if name.startswith('assets/') and (name.endswith(('.graphql','.json','.html','.sql','.txt','.js'))):
                target = OUT / 'assets' / name[7:]
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(name))
        write('classes.json',classes)
        write('dex-strings.json',sorted(strings))
        write('urls.json',sorted(s for s in strings if re.search(r'https?://|wss?://|/graphql',s)))
        resources = apk.get_android_resources()
        if resources:
            for locale in resources.get_locales(apk.get_package()):
                label = locale.replace('\x00','default').replace('/','_')
                (OUT / f'strings-{label}.xml').write_bytes(resources.get_string_resources(apk.get_package(),locale))
        write('summary.json',dict(entries=len(entries), classes=len(classes), strings=len(strings),
            dex=[e for e in entries if re.fullmatch(r'classes\d*\.dex',e['name'])],
            assets=[e for e in entries if e['name'].startswith('assets/')],
            native=[e for e in entries if e['name'].startswith('lib/')],
            layouts=sum('res/layout' in e['name'] for e in entries),
            packages=Counter('/'.join(c['name'].split('/')[:3]) for c in classes).most_common(60)))
    print((OUT/'package.json').read_text(encoding='utf-8'))
    print('classes',len(classes),'strings',len(strings),'files',len(entries))

if __name__ == '__main__':
    main()

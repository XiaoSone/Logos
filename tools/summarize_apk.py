"""Build reviewable evidence indexes from the immutable APK and parsed inventory."""
import io
import json
import re
import zipfile
from collections import Counter
from pathlib import Path
from lxml import etree
from elftools.elf.elffile import ELFFile
from androguard.core.apk import APK
from loguru import logger

logger.remove()
ROOT=Path(__file__).resolve().parents[1]
RAW=ROOT/'analysis/raw'
def write(name,data):
    (RAW/name).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')

apk=APK(str(ROOT/'wdbible_website_7_6_1.apk'))
resources=apk.get_android_resources()
public=etree.fromstring(resources.get_public_resources(apk.get_package()))
names={int(row.get('id'),16):row.get('type')+'/'+row.get('name') for row in public}
def resolve(match):
    value=int(match[2],16)
    return match[1]+names.get(value,match[2])
resolved=RAW/'layouts-resolved'; resolved.mkdir(exist_ok=True)
for path in (RAW/'layouts').glob('*.xml'):
    text=re.sub(r'([@?])([0-9A-F]{8})',resolve,path.read_text('utf-8'))
    (resolved/path.name).write_text(text,encoding='utf-8')
classes=json.loads((RAW/'classes.json').read_text('utf-8'))
business=[c for c in classes if c['name'].startswith('Lcom/wdbible/app/lib/businesslayer/')]
app=[c for c in classes if c['name'].startswith('Lcom/wdbible/app/wedevotebible/')]
write('business-interfaces.json',business)
write('app-modules.json',dict(classes=len(app),businessInterfaceClasses=len(business),
    modules=Counter(c['name'].split('/')[4] for c in app).most_common()))
native=[]
with zipfile.ZipFile(ROOT/'wdbible_website_7_6_1.apk') as archive:
    for name in archive.namelist():
        if name.startswith('lib/arm64-v8a/'):
            data=archive.read(name); elf=ELFFile(io.BytesIO(data))
            symbols=elf.get_section_by_name('.dynsym')
            dyn=elf.get_section_by_name('.dynamic')
            ascii_strings=[s.decode('ascii') for s in re.findall(rb'[\x20-\x7e]{8,}',data)]
            item=dict(name=name,machine=elf['e_machine'],bits=elf.elfclass,
                needed=[t.needed for t in dyn.iter_tags('DT_NEEDED')] if dyn else [],
                exported=[s.name for s in symbols.iter_symbols() if s['st_shndx']!='SHN_UNDEF'] if symbols else [],
                urls=sorted(set(s for s in ascii_strings if re.match(r'https?://',s))),
                graphqlCandidates=sorted(set(s for s in ascii_strings if re.search(r'\b(query|mutation|subscription)\s+\w+\s*[(\{]',s))))
            native.append(item)
write('native-analysis.json',native)
manifest=apk.get_android_manifest_xml(); android='{http://schemas.android.com/apk/res/android}'
application=manifest.find('application')
write('manifest-components.json',dict(application=dict(application.attrib),
    components=[dict(kind=c.tag,name=c.get(android+'name'),exported=c.get(android+'exported'),permission=c.get(android+'permission'),
       intents=[etree.tostring(i,encoding='unicode') for i in c.findall('intent-filter')])
       for c in application if c.tag in ('activity','service','receiver','provider')]))
print('app classes',len(app),'business interfaces',len(business),'native libraries',len(native))
print('modules',Counter(c['name'].split('/')[4] for c in app).most_common())
print('native GraphQL candidates',[(n['name'],len(n['graphqlCandidates'])) for n in native])

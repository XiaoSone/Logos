"""Independent content/encryption invariant checks; no APK-derived content is used."""
import base64
import hashlib
import json
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

root=Path(__file__).resolve().parents[1]
data=json.loads((root/'data/bible.json').read_text('utf-8'))
books=data['books']; verses=data['verses']; sections={s['id']:s for s in data['sections']}
assert len(books)==66 and sum(b['chapterCount'] for b in books)==1189
assert len({b['bookCode'] for b in books})==66
assert books[18]['bookCode']=='PS' and books[18]['chapterCount']==150
assert len({v['id'] for v in verses})==len(verses)
assert all(b['bookCode']==b['bookCode'].upper() for b in books)
footnote_ids=set()
for v in verses:
    book=next(b for b in books if b['bookCode']==v['bookCode'])
    assert int(v['id'])==book['bookOrder']*1000000+v['chapter']*1000+v['verse']
    s=sections[v['sectionId']]
    assert s['bookCode']==v['bookCode'] and s['chapter']==v['chapter']
    assert s['verseStart']<=v['verse']<=s['verseEnd']
    encoded=v['textZh'].encode('utf-16-le')
    for f in v['footnotes']:
        assert f['id'] not in footnote_ids
        footnote_ids.add(f['id'])
        actual=encoded[f['offsetStart']*2:f['offsetEnd']*2].decode('utf-16-le')
        assert actual=='（'+f['content']+'）',(v['verseRef'],actual)
assert len([v for v in verses if v['bookCode']=='PS' and v['chapter']==119])==176
ps46=next(v for v in verses if v['verseRef']=='PS 46:1')
assert ps46['textZh'].lstrip('　').startswith('神是我们的避难所')
assert '可拉后裔' in sections[ps46['sectionId']]['sectionTitle']
john=next(v for v in verses if v['verseRef']=='JOHN 3:16')
assert '神爱世人' in john['textZh']
assert next(v for v in verses if v['verseRef']=='GEN 1:1')['textZh']=='起初，　神创造天地。'
payload=(root/'data/bible.bin').read_bytes()
key=base64.b64decode((root/'.tools/bible-key.txt').read_text())
plain=AESGCM(key).decrypt(payload[:12],payload[12:],None)
assert hashlib.sha256(plain).hexdigest()==hashlib.sha256((root/'data/bible.json').read_bytes()).hexdigest()
index=json.loads((root/'data/bible_index.json').read_text('utf-8'))
assert 'verses' not in index
assert len(index['chapters'])==1189
print(f'PASS: 66 books / 1189 chapters / {len(verses)} atomic verse addresses / {len(footnote_ids)} stored footnotes / AES-GCM')

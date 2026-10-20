"""Import the pinned public-domain CUVs USFM snapshot into portable Logos data."""
import argparse
import base64
import hashlib
import json
import os
import re
import secrets
import zipfile
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[2]
ROWS = '''GEN|GEN|创世记|创|Genesis
EXO|EXOD|出埃及记|出|Exodus
LEV|LEV|利未记|利|Leviticus
NUM|NUM|民数记|民|Numbers
DEU|DEUT|申命记|申|Deuteronomy
JOS|JOSH|约书亚记|书|Joshua
JDG|JUDG|士师记|士|Judges
RUT|RUTH|路得记|得|Ruth
1SA|1SAM|撒母耳记上|撒上|1 Samuel
2SA|2SAM|撒母耳记下|撒下|2 Samuel
1KI|1KGS|列王纪上|王上|1 Kings
2KI|2KGS|列王纪下|王下|2 Kings
1CH|1CHR|历代志上|代上|1 Chronicles
2CH|2CHR|历代志下|代下|2 Chronicles
EZR|EZRA|以斯拉记|拉|Ezra
NEH|NEH|尼希米记|尼|Nehemiah
EST|ESTH|以斯帖记|斯|Esther
JOB|JOB|约伯记|伯|Job
PSA|PS|诗篇|诗|Psalms
PRO|PROV|箴言|箴|Proverbs
ECC|ECCL|传道书|传|Ecclesiastes
SNG|SONG|雅歌|歌|Song of Songs
ISA|ISA|以赛亚书|赛|Isaiah
JER|JER|耶利米书|耶|Jeremiah
LAM|LAM|耶利米哀歌|哀|Lamentations
EZK|EZEK|以西结书|结|Ezekiel
DAN|DAN|但以理书|但|Daniel
HOS|HOS|何西阿书|何|Hosea
JOL|JOEL|约珥书|珥|Joel
AMO|AMOS|阿摩司书|摩|Amos
OBA|OBAD|俄巴底亚书|俄|Obadiah
JON|JONAH|约拿书|拿|Jonah
MIC|MIC|弥迦书|弥|Micah
NAM|NAH|那鸿书|鸿|Nahum
HAB|HAB|哈巴谷书|哈|Habakkuk
ZEP|ZEPH|西番雅书|番|Zephaniah
HAG|HAG|哈该书|该|Haggai
ZEC|ZECH|撒迦利亚书|亚|Zechariah
MAL|MAL|玛拉基书|玛|Malachi
MAT|MATT|马太福音|太|Matthew
MRK|MARK|马可福音|可|Mark
LUK|LUKE|路加福音|路|Luke
JHN|JOHN|约翰福音|约|John
ACT|ACTS|使徒行传|徒|Acts
ROM|ROM|罗马书|罗|Romans
1CO|1COR|哥林多前书|林前|1 Corinthians
2CO|2COR|哥林多后书|林后|2 Corinthians
GAL|GAL|加拉太书|加|Galatians
EPH|EPH|以弗所书|弗|Ephesians
PHP|PHIL|腓立比书|腓|Philippians
COL|COL|歌罗西书|西|Colossians
1TH|1THESS|帖撒罗尼迦前书|帖前|1 Thessalonians
2TH|2THESS|帖撒罗尼迦后书|帖后|2 Thessalonians
1TI|1TIM|提摩太前书|提前|1 Timothy
2TI|2TIM|提摩太后书|提后|2 Timothy
TIT|TITUS|提多书|多|Titus
PHM|PHLM|腓利门书|门|Philemon
HEB|HEB|希伯来书|来|Hebrews
JAS|JAS|雅各书|雅|James
1PE|1PET|彼得前书|彼前|1 Peter
2PE|2PET|彼得后书|彼后|2 Peter
1JN|1JOHN|约翰一书|约一|1 John
2JN|2JOHN|约翰二书|约二|2 John
3JN|3JOHN|约翰三书|约三|3 John
JUD|JUDE|犹大书|犹|Jude
REV|REV|启示录|启|Revelation'''

def clean_inline(raw, footnotes=None):
    raw = re.sub(r'\\x .*?\\x\*', '', raw, flags=re.S)
    def footnote(match):
        content = re.split(r'\\ft\s*', match[0], maxsplit=1)[-1]
        content = re.sub(r'\\[+a-zA-Z0-9]+\*?\s?', '', content).strip(' \r\n\t')
        return '\ue000（' + content + '）\ue001'
    raw = re.sub(r'\\f .*?\\f\*', footnote, raw, flags=re.S)
    raw = re.sub(r'\\[+a-zA-Z0-9]+\*? ?', '', raw)
    raw = re.sub(r'[ \r\n\t]+', '', raw)  # Preserve U+3000 full-width spaces.
    text = ''
    cursor = 0
    for match in re.finditer('\ue000(.*?)\ue001',raw):
        text += raw[cursor:match.start()]
        start = len(text.encode('utf-16-le'))//2
        text += match[1]
        if footnotes is not None:
            footnotes.append(dict(content=match[1][1:-1],offsetStart=start,
                offsetEnd=len(text.encode('utf-16-le'))//2))
        cursor = match.end()
    return text+raw[cursor:]

def parse_book(source, meta):
    code = meta['bookCode']
    chapters, verses, sections = [], [], []
    chapter, section_title, poetry = 0, None, False
    current, active_section = None, None
    def flush_verse():
        nonlocal current, active_section
        if not current:
            return
        notes = []
        text = clean_inline(current.pop('raw'),notes)
        current['textZh'] = text
        current['footnotes'] = []
        for i, note in enumerate(notes):
            current['footnotes'].append(dict(id=f"{current['id']}.f{i}",**note))
        if active_section is None:
            index = 1 + sum(s['chapter']==chapter for s in sections)
            active_section = dict(id=f'{code}.{chapter}.s{index}',bookCode=code,chapter=chapter,
                sectionIndex=index,sectionTitle=section_title,verseStart=current['verse'],
                verseEnd=current['verse'],verseCount=0,isPoetry=poetry)
            sections.append(active_section)
        bridge_end = current.pop('bridgeEnd')
        active_section['verseEnd'] = bridge_end
        active_section['verseCount'] += bridge_end-current['verse']+1
        active_section['isPoetry'] |= poetry
        current['sectionId'] = active_section['id']
        for number in range(current['verse'],bridge_end+1):
            verse_id=str(meta['bookOrder']*1000000+chapter*1000+number)
            verses.append({**current,'id':verse_id, 'verse':number,
                'verseRef':f'{code} {chapter}:{number}',
                'footnotes':[{**f,'id':f'{verse_id}.f{i}'} for i,f in enumerate(current['footnotes'])]})
        current = None
    for line in source.splitlines():
        match = re.match(r'^\\(\w+)\s*(.*)', line)
        if not match:
            if current:
                current['raw'] += line
            continue
        marker, value = match.groups()
        if marker == 'c':
            flush_verse()
            chapter = int(value.strip())
            chapters.append(chapter)
            active_section, section_title, poetry = None, None, False
        elif marker in ('s1','s2','s3'):
            flush_verse()
            active_section, section_title, poetry = None, clean_inline(value), False
        elif marker == 'v':
            flush_verse()
            number, text = value.split(' ',1)
            if not re.fullmatch(r'\d+(?:-\d+)?',number):
                raise ValueError(f'Unreviewed verse number: {code} {chapter}:{number}')
            verse = int(number.split('-')[0])
            end = int(number.split('-')[-1])
            current = dict(id=f'{code}.{chapter}.{verse}',bookCode=code,chapter=chapter,
                verse=verse,verseRef=f'{code} {chapter}:{verse}',raw=text,
                bridgeEnd=end,bridgeStart=verse,verseLabel=number)
        elif marker == 'd':
            flush_verse()
            # A Psalm's descriptive title is metadata, never verse-one text.
            title = clean_inline(value)
            section_title = '\n'.join(t for t in (section_title, title) if t)
            active_section = None
        elif marker == 'sp':
            flush_verse()
            # Speaker labels in Song of Songs begin a new displayed section.
            section_title, active_section = clean_inline(value), None
        elif marker in ('q','q1','q2','q3','qr','qa'):
            poetry = True
            if current:
                current['raw'] += value
        elif marker in ('p','m','b','pi','pi1','li1','li2'):
            if current:
                current['raw'] += value
        elif marker in ('id','h','toc1','toc2','toc3','mt','mt1','mt2','ms1','r','rem','ide','usfm'):
            continue
        else:
            raise ValueError(f'Unreviewed USFM marker: {marker} in {code}')
    flush_verse()
    meta['chapterCount'] = max(chapters)
    assert chapters == list(range(1,len(chapters)+1)), code
    return verses, sections

def run(archive_path):
    digest = hashlib.file_digest(archive_path.open('rb'),'sha256').hexdigest()
    checksum = Path(__file__).with_name('checksums.txt')
    if checksum.exists() and checksum.read_text().split()[0] != digest:
        raise ValueError('Source SHA-256 changed; review the snapshot before updating checksums.txt')
    checksum.write_text(f'{digest}  cmn-cu89s_usfm.zip\n')
    books, verses, sections = [], [], []
    with zipfile.ZipFile(archive_path) as archive:
        sources = {}
        for name in archive.namelist():
            if name.endswith('.usfm'):
                text = archive.read(name).decode('utf-8-sig')
                sources[re.search(r'\\id (\w+)',text)[1]] = text
        for order,row in enumerate(ROWS.splitlines(),1):
            usfm,code,zh,abbr,en = row.split('|')
            meta = dict(id=str(order),bookCode=code,bookNameZh=zh,bookNameAbbr=abbr,
                bookNameEn=en,testament=1 if order<=39 else 2,bookOrder=order,
                aliases=list(dict.fromkeys([code,usfm,zh,abbr,en])))
            v,s = parse_book(sources[usfm],meta)
            books.append(meta); verses.extend(v); sections.extend(s)
    assert len(books)==66 and sum(b['chapterCount'] for b in books)==1189
    assert books[18]['chapterCount']==150
    assert len({v['id'] for v in verses})==len(verses)
    data = dict(version='b1',books=books,verses=verses,sections=sections)
    output = ROOT/'data'; output.mkdir(exist_ok=True)
    raw = json.dumps(data,ensure_ascii=False,separators=(',',':')).encode('utf-8')
    (output/'bible.json').write_bytes(raw)
    index = dict(version='b1',books=books,sections=sections,chapters=[dict(bookCode=b['bookCode'],
        chapter=c,verseCount=sum(v['bookCode']==b['bookCode'] and v['chapter']==c for v in verses))
        for b in books for c in range(1,b['chapterCount']+1)])
    (output/'bible_index.json').write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    key_path=ROOT/'.tools'/'bible-key.txt'
    key = base64.b64decode(os.environ['BIBLE_MASTER_KEY']) if os.environ.get('BIBLE_MASTER_KEY') else (
        base64.b64decode(key_path.read_text()) if key_path.exists() else secrets.token_bytes(32))
    assert len(key)==32,'Master key must contain exactly 32 bytes'
    key_path.write_text(base64.b64encode(key).decode('ascii'))
    nonce=secrets.token_bytes(12)
    (output/'bible.bin').write_bytes(nonce+AESGCM(key).encrypt(nonce,raw,None))
    report=dict(source='https://ebible.org/Scriptures/cmn-cu89s_usfm.zip',license='Public Domain',
        sourceSha256=digest,dataSha256=hashlib.sha256(raw).hexdigest(),books=len(books),
        chapters=sum(b['chapterCount'] for b in books),verses=len(verses),sections=len(sections),
        footnotes=sum(len(v['footnotes']) for v in verses),
        sourceVerseUnits=sum(v['verse']==v['bridgeStart'] for v in verses),
        sourceFootnotes=sum(len(v['footnotes']) for v in verses if v['verse']==v['bridgeStart']),
        encryption='AES-256-GCM: 12-byte nonce + ciphertext + 16-byte tag; key excluded from package')
    (output/'import-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('archive',type=Path)
    run(parser.parse_args().archive)

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/bible_models.dart';
import 'package:logos/data/bible_repository.dart';
import 'package:logos/data/local_store.dart';
import 'package:drift/native.dart';
import 'package:logos/ui/search_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BibleRepository bible;
  late LocalStore store;
  setUp(() async {
    store = LocalStore(NativeDatabase.memory());
    bible = BibleRepository(store);
    final index = jsonDecode(
      await rootBundle.loadString('assets/bible_index.json'),
    );
    bible.books = (index['books'] as List)
        .map((b) => Book(b as Map<String, dynamic>))
        .toList();
    bible.verses = [
      const Verse({
        'id': '43003016',
        'bookCode': 'JOHN',
        'chapter': 3,
        'verse': 16,
        'textZh': '「　神爱世人，甚至将他的独生子赐给他们。',
        'verseRef': 'JOHN 3:16',
        'sectionId': 'JOHN.3.s1',
        'footnotes': [],
      }),
      const Verse({
        'id': '43003017',
        'bookCode': 'JOHN',
        'chapter': 3,
        'verse': 17,
        'textZh': '因为　神差他的儿子降世，不是要定世人的罪。',
        'verseRef': 'JOHN 3:17',
        'sectionId': 'JOHN.3.s1',
        'footnotes': [],
      }),
    ];
    bible.byId = {for (final v in bible.verses) v.id: v};
    bible.byChapter = {'JOHN.3': bible.verses};
  });
  tearDown(() => store.close());
  test('canon metadata has 66 books and 1189 chapters', () {
    expect(bible.books.length, 66);
    expect(bible.books.fold(0, (n, b) => n + b.chapters), 1189);
    expect(bible.book('JHN').code, 'JOHN');
    expect(bible.book('诗').code, 'PS');
  });
  test(
    'Chinese, English, fullwidth, ranges and deep links resolve identically',
    () {
      for (final reference in [
        '约3:16',
        'JOHN 3:16',
        'John ３：１６',
        'logos://verse/JOHN.3.16',
      ]) {
        expect(
          bible.resolve(reference).single.id,
          '43003016',
          reason: reference,
        );
      }
      expect(bible.resolve('约3:16-17').length, 2);
      expect(bible.resolve('约3:17-16'), isEmpty);
      expect(bible.resolve('约3:999'), isEmpty);
      expect(bible.resolve('不存在1:1'), isEmpty);
    },
  );
  test('keyword search is literal and copy preserves fullwidth spacing', () {
    expect(bible.search('神爱世人').single.number, 16);
    expect(bible.search('%'), isEmpty);
    expect(bible.search('_'), isEmpty);
    expect(bible.copyText(bible.verses.first), '约3:16　「　神爱世人，甚至将他的独生子赐给他们。');
    expect(highlight('平安平安', '平安').where((s) => s.style != null).length, 2);
  });
  Verse referenceVerse(
    int number, {
    String code = 'JOHN',
    int chapter = 3,
    String? label,
  }) => Verse({
    'bookCode': code,
    'chapter': chapter,
    'verse': number,
    'verseLabel': label,
  });

  test('share references compress consecutive verses without filling gaps', () {
    expect(
      bible.formatReferences([
        for (final number in [11, 4, 1, 9, 2, 5, 3, 3]) referenceVerse(number),
      ]),
      '约翰福音 3:1-5,9,11',
    );
    expect(bible.formatReferences([referenceVerse(16)]), '约翰福音 3:16');
    expect(bible.formatReferences([]), '');
  });

  test('share references keep chapter, book and source bridge boundaries', () {
    expect(
      bible.formatReferences([
        referenceVerse(2, chapter: 4),
        referenceVerse(1, code: 'GEN', chapter: 1),
        referenceVerse(36),
        referenceVerse(1, chapter: 4),
      ]),
      '创世记 1:1; 约翰福音 3:36; 约翰福音 4:1-2',
    );
    expect(
      bible.formatReferences([
        referenceVerse(12, label: '12-13'),
        referenceVerse(14),
        referenceVerse(16),
      ]),
      '约翰福音 3:12-14,16',
    );
  });

  test(
    'notes and feed commit atomically, upsert does not duplicate note',
    () async {
      const note = {
        'id': 'note-1',
        'content': '盼望',
        'verseIds': ['43003016'],
        'updatedAt': '2026-10-16T00:00:00Z',
      };
      const event = {
        'id': 'event-1',
        'type': 'NOTE_CREATED',
        'content': '盼望',
        'createdAt': '2026-10-16T00:00:00Z',
      };
      await store.put('note', 'note-1', note, record: event);
      await store.put('note', 'note-1', {...note, 'content': '盼望与信心'});
      expect((await store.list('note')).single['content'], '盼望与信心');
      expect((await store.feed()).length, 1);
      await store.remove('note', 'note-1');
      expect(await store.list('note'), isEmpty);
      expect((await store.feed()).length, 1);
    },
  );
}

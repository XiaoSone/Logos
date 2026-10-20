import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/bible_models.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/state/app_controller.dart';

class HighlightTestController extends AppController {
  HighlightTestController() : super(store: LocalStore(NativeDatabase.memory()));

  @override
  Future<void> boot() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HighlightTestController app;
  late List<Verse> verses;
  const yellow = '#F2D893';
  const blue = '#A9D0DF';

  Future<int> storedHighlights() async =>
      (await app.store
              .customSelect(
                "SELECT COUNT(*) AS count FROM feed_record WHERE type='SCRIPTURE_HIGHLIGHT'",
              )
              .getSingle())
          .read<int>('count');

  setUp(() {
    app = HighlightTestController();
    app.bible.books = [
      const Book({
        'bookCode': 'JOHN',
        'bookNameZh': '约翰福音',
        'bookNameAbbr': '约',
        'aliases': ['JOHN'],
      }),
    ];
    verses = [
      for (final number in [7, 8])
        Verse({
          'id': 'JOHN.3.$number',
          'bookCode': 'JOHN',
          'chapter': 3,
          'verse': number,
          'textZh': '第 $number 节高亮经文。',
        }),
    ];
  });

  tearDown(() async {
    await app.store.close();
    app.dispose();
  });

  test(
    'tapping the active color removes highlight and automatic bookmark',
    () async {
      expect(await app.toggleHighlights(verses, yellow), isFalse);
      expect(app.bookmarks, hasLength(2));
      expect(await app.toggleHighlights(verses, yellow), isTrue);
      expect(app.bookmarks, isEmpty);
      expect(await storedHighlights(), 0);
    },
  );

  test(
    'clearing multiple highlights retains bookmarks only for verses with notes',
    () async {
      for (var i = 0; i < 2; i++) {
        await app.saveNote(
          title: '笔记 $i',
          content: '内容',
          verseIds: [verses.first.id],
          tags: [],
        );
      }
      expect(app.noteCountFor(verses.first.id), 2);
      await app.toggleHighlights(verses, yellow);
      expect(await app.toggleHighlights(verses, yellow), isTrue);
      expect(app.bookmarkFor(verses.first.id), isNotNull);
      expect(app.bookmarkFor(verses.first.id)!['color'], isNull);
      expect(app.bookmarkFor(verses.last.id), isNull);
      expect(await storedHighlights(), 0);
      expect(app.notes, hasLength(2));
      await app.removeNote(app.notes.first['id'] as String);
      expect(app.noteCountFor(verses.first.id), 1);
    },
  );

  test(
    'a mixed color selection unifies the color before a subsequent tap clears it',
    () async {
      await app.bookmark(verses.first, color: yellow);
      await app.bookmark(verses.last, color: blue);
      expect(await app.toggleHighlights(verses, yellow), isFalse);
      expect(
        app.bookmarks.every((bookmark) => bookmark['color'] == yellow),
        isTrue,
      );
      expect(await app.toggleHighlights(verses, yellow), isTrue);
      expect(app.bookmarks, isEmpty);
    },
  );

  test(
    'cancelled and legacy stale highlights are deleted from the database',
    () async {
      await app.bookmark(verses.first, color: yellow);
      expect(app.records.single['type'], 'SCRIPTURE_HIGHLIGHT');
      await app.store.remove('bookmark', verses.first.id);
      expect(await storedHighlights(), 0);
      await app.refresh();
      expect(app.bookmarks, isEmpty);
      expect(app.records, isEmpty);
      await app.refresh();
      expect(app.records, isEmpty);
      expect(await storedHighlights(), 0);
      // Upgrading also deletes stale history already left by older versions.
      await app.store.addFeed({
        'id': 'legacy-highlight',
        'type': 'SCRIPTURE_HIGHLIGHT',
        'verseId': verses.last.id,
        'color': yellow,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      await app.refresh();
      expect(app.records, isEmpty);
      expect(await storedHighlights(), 0);
    },
  );

  test(
    'changing color and re-highlighting show only the current latest card',
    () async {
      final verse = verses.first;
      await app.bookmark(verse, color: yellow);
      final original = app.records.single['id'];
      await app.store.addFeed({
        'id': 'legacy-duplicate',
        'type': 'SCRIPTURE_HIGHLIGHT',
        'verseId': verse.id,
        'color': yellow,
        'createdAt': '2000-01-01T00:00:00Z',
      });
      expect(await storedHighlights(), 2);
      await app.refresh();
      expect(await storedHighlights(), 1);
      expect(app.records.single['id'], original);
      await app.bookmark(verse, color: yellow);
      expect(app.records, hasLength(1));
      expect(await storedHighlights(), 1);
      expect(app.records.single['id'], isNot(original));
      await app.bookmark(verse, color: blue);
      expect(app.records, hasLength(1));
      expect(app.records.single['color'], blue);
      expect(await storedHighlights(), 1);
      await app.removeBookmark(verse.id);
      expect(app.records, isEmpty);
      expect(await storedHighlights(), 0);
      await app.bookmark(verse, color: yellow);
      expect(app.records, hasLength(1));
      expect(app.records.single['color'], yellow);
      expect(app.records.single['id'], isNot(original));
      expect(await storedHighlights(), 1);
      await app.bookmark(verse);
      expect(await storedHighlights(), 0);
      expect(app.records.map((record) => record['type']), ['BOOKMARK_ADDED']);
    },
  );

  test(
    'cancelling a highlight preserves other verses and other record types',
    () async {
      for (final type in [
        'NOTE_CREATED',
        'SCRIPTURE_SHARED',
        'BOOKMARK_ADDED',
      ]) {
        await app.store.addFeed({
          'id': type,
          'type': type,
          'verseId': verses.first.id,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
      await app.bookmark(verses.first, color: yellow);
      await app.bookmark(verses.last, color: blue);
      await app.removeBookmark(verses.first.id);
      expect(await storedHighlights(), 1);
      expect(
        app.records.map((record) => record['type']),
        unorderedEquals([
          'SCRIPTURE_HIGHLIGHT',
          'NOTE_CREATED',
          'SCRIPTURE_SHARED',
          'BOOKMARK_ADDED',
        ]),
      );
      expect(
        app.records.singleWhere(
          (record) => record['type'] == 'SCRIPTURE_HIGHLIGHT',
        )['verseId'],
        verses.last.id,
      );
    },
  );

  test(
    'a failed color change rolls back the mark and record deletion together',
    () async {
      await app.bookmark(verses.first, color: yellow);
      final recordId = app.records.single['id'];
      await app.store.customStatement('''
      CREATE TRIGGER reject_highlight BEFORE INSERT ON feed_record
      WHEN NEW.type='SCRIPTURE_HIGHLIGHT'
      BEGIN SELECT RAISE(ABORT, 'test failure'); END
    ''');
      await expectLater(
        app.bookmark(verses.first, color: blue),
        throwsException,
      );
      await app.refresh();
      expect(app.bookmarkFor(verses.first.id)?['color'], yellow);
      expect(app.records.single['id'], recordId);
      expect(await storedHighlights(), 1);
    },
  );
}

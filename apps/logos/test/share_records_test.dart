import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/bible_models.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/state/app_controller.dart';

class ShareTestController extends AppController {
  ShareTestController() : super(store: LocalStore(NativeDatabase.memory()));

  @override
  Future<void> boot() async {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  late ShareTestController app;
  late List<Verse> verses;
  late List<String> sharedTexts;

  setUp(() {
    app = ShareTestController();
    verses = [
      for (final number in [16, 18])
        Verse({
          'id': 'JOHN.3.$number',
          'bookCode': 'JOHN',
          'chapter': 3,
          'verse': number,
          'textZh': '第 $number 节分享经文。',
        }),
    ];
    app.bible.books = [
      const Book({
        'bookCode': 'JOHN',
        'bookNameZh': '约翰福音',
        'bookNameAbbr': '约',
        'bookNameEn': 'John',
        'chapterCount': 21,
        'bookOrder': 43,
        'testament': 2,
        'aliases': ['JOHN', '约翰福音', '约'],
      }),
    ];
    sharedTexts = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      sharedTexts.add((call.arguments as Map)['text'] as String);
      return 'test.share.target';
    });
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await app.store.close();
    app.dispose();
  });

  test(
    'each share persists one complete record regardless of verse count',
    () async {
      expect(await app.shareVerses(verses), isTrue);
      expect(sharedTexts, [
        '${verses.map(app.bible.copyText).join('\n')}\nlogos://verse/JOHN.3.16',
      ]);
      expect(app.records, hasLength(1));
      final record = app.records.single;
      expect(record['type'], 'SCRIPTURE_SHARED');
      expect(record['verseId'], verses.first.id);
      expect(record['verseIds'], verses.map((verse) => verse.id).toList());
      expect(record['content'], verses.map(app.bible.copyText).join('\n'));
      await app.refresh();
      expect(app.records.single, record);
      expect(await app.shareVerses([verses.last]), isTrue);
      expect(app.records, hasLength(2));
      expect(app.records.map((record) => record['id']).toSet(), hasLength(2));
      expect(
        app.records.where((record) => (record['verseIds'] as List).length == 1),
        hasLength(1),
      );
    },
  );

  test(
    'dismissed, unavailable and failed shares create no records and allow retry',
    () async {
      for (final outcome in [
        '',
        'dev.fluttercommunity.plus/share/unavailable',
      ]) {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => outcome,
        );
        expect(await app.shareVerses(verses), isFalse);
        expect(await app.store.feed(), isEmpty);
      }
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        throw PlatformException(code: 'share_failed');
      });
      await expectLater(
        app.shareVerses(verses),
        throwsA(isA<PlatformException>()),
      );
      expect(await app.store.feed(), isEmpty);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => 'test.share.target',
      );
      expect(await app.shareVerses(verses), isTrue);
      expect(app.records, hasLength(1));
    },
  );

  test(
    'pending share cannot launch twice or record before a target is chosen',
    () async {
      final result = Completer<String>();
      var calls = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) {
        calls++;
        return result.future;
      });
      expect(await app.shareVerses([]), isFalse);
      expect(calls, 0);
      final pending = app.shareVerses(verses);
      expect(await app.shareVerses(verses), isFalse);
      expect(await app.store.feed(), isEmpty);
      result.complete('test.share.target');
      expect(await pending, isTrue);
      expect(calls, 1);
      expect(await app.store.feed(), hasLength(1));
    },
  );

  test(
    'legacy selection records are deleted while other history is preserved',
    () async {
      for (final type in ['VERSE_SELECTED', 'BOOKMARK_ADDED', 'NOTE_CREATED']) {
        await app.store.addFeed({
          'id': type,
          'type': type,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
      await app.bookmark(verses.first, color: '#F2D893');
      await app.refresh();
      final selections = await app.store
          .customSelect(
            "SELECT COUNT(*) AS count FROM feed_record WHERE type='VERSE_SELECTED'",
          )
          .getSingle();
      expect(selections.read<int>('count'), 0);
      expect(
        app.records.map((record) => record['type']),
        unorderedEquals([
          'BOOKMARK_ADDED',
          'NOTE_CREATED',
          'SCRIPTURE_HIGHLIGHT',
        ]),
      );
    },
  );
}

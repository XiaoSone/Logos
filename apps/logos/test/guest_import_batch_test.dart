import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/guest_import_batch.dart';
import 'package:logos/data/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const time = '2026-10-19T00:00:00.000Z';
  late LocalStore store;
  setUp(() => store = LocalStore(NativeDatabase.memory()));
  tearDown(() => store.close());

  test(
    'maps all entity kinds, deletion and full share references to the import contract',
    () async {
      await store.put('bookmark', '43003016', {
        'verseId': '43003016',
        'color': '#F2D893',
        'note': '收藏备注',
        'createdAt': time,
        'updatedAt': time,
      });
      await store.remove('bookmark', '43003016');
      await store.put('note', 'note', {
        'title': '标题',
        'content': '正文',
        'verseIds': ['43003016', '43003017'],
        'tags': ['带,逗号'],
        'createdAt': time,
        'updatedAt': time,
      });
      await store.put('progress', 'JOHN.3', {
        'bookCode': 'JOHN',
        'chapter': 3,
        'verse': 16,
        'updatedAt': time,
      });
      await store.addFeed({
        'id': 'share',
        'type': 'SCRIPTURE_SHARED',
        'content': '完整分享',
        'verseIds': ['43003016', '43003017'],
        'createdAt': time,
      });
      final batch = GuestImportBatch(await store.pendingChanges());
      String reference(String id) => 'JOHN 3:${int.parse(id) % 1000}';
      final items = batch.items(reference);
      expect(
        items.singleWhere((i) => i['type'] == 'BOOKMARK'),
        containsPair('operation', 'DELETE'),
      );
      expect(
        items.singleWhere((i) => i['type'] == 'NOTE'),
        containsPair('tags', ['带,逗号']),
      );
      expect(
        items.singleWhere((i) => i['type'] == 'PROGRESS'),
        containsPair('verse', 16),
      );
      expect(
        items.singleWhere((i) => i['type'] == 'FEED_RECORD'),
        containsPair('verseRefs', ['JOHN 3:16', 'JOHN 3:17']),
      );
      expect(
        items.singleWhere((i) => i['type'] == 'FEED_RECORD')['updatedAt'],
        time,
      );
      expect(
        batch.items(reference),
        items,
        reason: 'retry must preserve the revision payload',
      );
      expect(
        await store.pendingChanges(),
        hasLength(4),
        reason: 'preparation never uploads or acknowledges data',
      );
    },
  );

  test(
    'partial success acknowledges only submitted versions and retains failed or newly edited rows',
    () async {
      for (final id in ['one', 'two', 'three']) {
        await store.put('note', id, {'content': id, 'updatedAt': time});
      }
      final batch = GuestImportBatch(await store.pendingChanges());
      await store.put('note', 'three', {
        'content': '请求发出后的编辑',
        'updatedAt': time,
      });
      await batch.acknowledge(store, failed: ['two']);
      expect(
        (await store.pendingChanges()).map((c) => c.clientKey),
        unorderedEquals(['two', 'three']),
      );
      expect(await store.list('note'), hasLength(3));
    },
  );

  test(
    'invalid responses and reference conversion failures leave the queue intact',
    () async {
      await store.put('note', 'note', {
        'content': '正文',
        'verseIds': ['invalid'],
        'updatedAt': time,
      });
      final batch = GuestImportBatch(await store.pendingChanges());
      expect(
        () => batch.items((_) => throw StateError('引用未就绪')),
        throwsStateError,
      );
      expect(
        () => batch.acknowledge(store, failed: ['unexpected']),
        throwsArgumentError,
      );
      expect(await store.pendingChanges(), hasLength(1));
      expect(() => GuestImportBatch([]), throwsArgumentError);
    },
  );
}

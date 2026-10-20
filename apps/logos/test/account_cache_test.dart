import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/local_store.dart';
import 'support/account_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore guest;
  late LocalStore account;
  setUp(() {
    guest = LocalStore(NativeDatabase.memory());
    account = LocalStore.named(
      'test_account',
      executor: NativeDatabase.memory(),
    );
  });
  tearDown(() async {
    await guest.close();
    await account.close();
  });

  test(
    'guest adoption keeps newer account values and tombstones, merges progress, and preserves shares',
    () async {
      await addTestNote(guest, 'deleted-note');
      await guest.put('bookmark', '43003016', {
        'verseId': '43003016',
        'color': '#F2D893',
        'updatedAt': testTime,
      });
      await guest.put('progress', 'JOHN.3', {
        'bookCode': 'JOHN',
        'chapter': 3,
        'verse': 16,
        'updatedAt': testTime,
      });
      await guest.addFeed({
        'id': 'share',
        'type': 'SCRIPTURE_SHARED',
        'verseIds': ['43003016', '43003017'],
        'content': '完整分享',
        'createdAt': testTime,
      });
      final shareRevision = (await guest.pendingChanges())
          .singleWhere((c) => c.kind == 'feed')
          .revision;
      await addTestNote(account, 'deleted-note');
      await account.remove('note', 'deleted-note');
      const later = '2026-10-20T00:00:00.000Z';
      await account.put('bookmark', '43003016', {
        'verseId': '43003016',
        'color': '#A9D0DF',
        'updatedAt': later,
      });
      await account.put('progress', 'JOHN.3', {
        'bookCode': 'JOHN',
        'chapter': 3,
        'verse': 20,
        'updatedAt': later,
      });
      final snapshot = await guest.snapshot();
      await account.adoptGuest(snapshot, 'transfer-1');
      expect(await account.list('note'), isEmpty);
      expect((await account.list('bookmark')).single['color'], '#A9D0DF');
      expect((await account.list('progress')).single['verse'], 20);
      expect((await account.feed()).single['verseIds'], [
        '43003016',
        '43003017',
      ]);
      expect(
        (await account.pendingChanges())
            .singleWhere((c) => c.kind == 'feed')
            .revision,
        shareRevision,
      );
      final revisions = (await account.pendingChanges())
          .map((c) => c.revision)
          .toList();
      await account.adoptGuest(snapshot, 'transfer-1');
      expect(
        (await account.pendingChanges()).map((c) => c.revision).toList(),
        revisions,
      );
      expect(
        await guest.list('note'),
        hasLength(1),
        reason: 'destination commit does not clear its source',
      );
    },
  );

  test(
    'cloud cache replacement preserves local edits and deletes while removing stale synced rows',
    () async {
      await addTestNote(account, 'removed-remotely');
      await account.acknowledgeChanges(await account.pendingChanges());
      await addTestNote(account, 'edited', content: '拉取期间的编辑');
      await addTestNote(account, 'deleted');
      await account.remove('note', 'deleted');
      final before = (await account.pendingChanges())
          .map((c) => c.revision)
          .toSet();
      Map<String, dynamic> note(String id, String content) => {
        'id': id,
        'content': content,
        'verseIds': [],
        'tags': [],
        'updatedAt': testTime,
      };
      await account.replaceSynced(
        StoreSnapshot(
          {
            'note': [
              note('edited', '旧云端正文'),
              note('deleted', '旧云端正文'),
              note('cloud-only', '云端新笔记'),
            ],
          },
          [],
          [],
          {},
        ),
      );
      final notes = await account.list('note');
      expect(
        notes.map((n) => n['id']),
        unorderedEquals(['edited', 'cloud-only']),
      );
      expect(
        notes.singleWhere((n) => n['id'] == 'edited')['content'],
        '拉取期间的编辑',
      );
      expect(
        (await account.pendingChanges()).map((c) => c.revision).toSet(),
        before,
      );
    },
  );

  test(
    'an invalid cloud cache rolls back the entire replacement and leaves pending work intact',
    () async {
      await addTestNote(account, 'local-note');
      final revision = (await account.pendingChanges()).single.revision;
      await expectLater(
        account.replaceSynced(
          const StoreSnapshot(
            {
              'note': [
                {
                  'id': 'invalid-cloud-note',
                  'content': null,
                  'updatedAt': testTime,
                },
              ],
            },
            [],
            [],
            {},
          ),
        ),
        throwsException,
      );
      expect((await account.list('note')).single['id'], 'local-note');
      expect((await account.pendingChanges()).single.revision, revision);
    },
  );
}

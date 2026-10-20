import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/bible_models.dart';
import 'package:logos/data/bible_repository.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/state/account_manager.dart';
import 'support/account_support.dart';

// Run only against a disposable test backend/database, never a user's account DB.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const server = String.fromEnvironment('LOGOS_ACCOUNT_TEST_URL');
  test(
    'real GraphQL login, guest import, account pull, edit, delete, A/B isolation and restoration',
    () async {
      final originalHttp = HttpOverrides.current;
      HttpOverrides.global = null;
      final directory = await Directory.systemTemp.createTemp(
        'logos-account-http-',
      );
      final credentials = MemoryCredentials();
      AccountManager makeManager() => AccountManager(
        guest: LocalStore(NativeDatabase(File('${directory.path}/guest.db'))),
        openStore: (name) => LocalStore.named(
          name,
          executor: NativeDatabase(File('${directory.path}/$name.db')),
        ),
        credentials: credentials,
        retryDelay: const Duration(days: 1),
        debounceDelay: const Duration(days: 1),
      );
      var manager = makeManager();
      final index =
          jsonDecode(await rootBundle.loadString('assets/bible_index.json'))
              as Map;
      final bible = BibleRepository(manager.guest)
        ..books = [
          for (final book in index['books'] as List)
            Book(book as Map<String, dynamic>),
        ];
      manager.referenceForId = bible.referenceForId;
      final random = Random.secure();
      final firstPhone =
          '199${random.nextInt(100000000).toString().padLeft(8, '0')}';
      var secondPhone = firstPhone;
      while (secondPhone == firstPhone) {
        secondPhone =
            '199${random.nextInt(100000000).toString().padLeft(8, '0')}';
      }
      Future<void> connect(String phone) => manager.login(
        server: server,
        phone: phone,
        code: '246810',
        invite: 'LOGOS-LOCAL',
        deviceId: 'account-http-test-device',
      );
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        await manager.guest.put('note', 'http-note', {
          'title': '真实往返',
          'content': '原始正文',
          'tags': ['含,逗号', '引"号'],
          'verseIds': ['43003016', '43003017'],
          'createdAt': now,
          'updatedAt': now,
        });
        await manager.guest.put('bookmark', '43003016', {
          'verseId': '43003016',
          'color': '#F2D893',
          'updatedAt': now,
        });
        await manager.guest.put('progress', 'JOHN.3', {
          'bookCode': 'JOHN',
          'chapter': 3,
          'verse': 16,
          'updatedAt': now,
        });
        await manager.guest.addFeed({
          'id': 'http-share',
          'type': 'SCRIPTURE_SHARED',
          'content': '两节分享快照',
          'verseIds': ['43003016', '43003017'],
          'createdAt': now,
        });
        await connect(firstPhone);
        await manager.sync();
        expect(manager.syncError, isNull);
        expect(manager.pendingCount, 0);
        expect((await manager.store.list('note')).single['tags'], [
          '含,逗号',
          '引"号',
        ]);
        expect(
          (await manager.store.feed()).singleWhere(
            (r) => r['type'] == 'SCRIPTURE_SHARED',
          )['verseIds'],
          ['43003016', '43003017'],
        );
        final first = manager.account!;
        final note = (await manager.store.list('note')).single;
        await manager.withStore((store) async {
          await store.put('note', 'http-note', {
            ...note,
            'content': '更新正文',
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          });
          await store.remove('bookmark', '43003016');
        });
        await manager.sync();
        expect(manager.syncError, isNull);
        final cloudA = await manager.remote.fetch(first);
        expect(cloudA.data['note']!.single['content'], '更新正文');
        expect(cloudA.data['bookmark'], isEmpty);
        await manager.logout();
        expect(await manager.store.list('note'), isEmpty);
        await connect(secondPhone);
        await manager.sync();
        expect(manager.syncError, isNull);
        expect(manager.account!.userId, isNot(first.userId));
        expect(await manager.store.list('note'), isEmpty);
        await manager.withStore(
          (store) => addTestNote(
            store,
            'B-note',
            content: '只属于 B',
            updated: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        await manager.sync();
        expect(manager.syncError, isNull);
        expect(
          (await manager.remote.fetch(first)).data['note']!.single['id'],
          'http-note',
        );
        await manager.logout();
        await connect(firstPhone);
        await manager.sync();
        expect(manager.syncError, isNull);
        expect((await manager.store.list('note')).single['content'], '更新正文');
        await manager.withStore((store) => store.remove('note', 'http-note'));
        await manager.sync();
        expect(manager.syncError, isNull);
        expect((await manager.remote.fetch(first)).data['note'], isEmpty);
        await manager.close();
        manager.dispose();
        manager = makeManager()..referenceForId = bible.referenceForId;
        await manager.restore(server);
        expect(manager.account!.userId, first.userId);
        expect((await manager.store.list('progress')).single['verse'], 16);
        expect(
          (await manager.store.feed()).where(
            (r) => r['type'] == 'SCRIPTURE_SHARED',
          ),
          hasLength(1),
        );
      } finally {
        await manager.close();
        manager.dispose();
        await directory.delete(recursive: true);
        HttpOverrides.global = originalHttp;
      }
    },
    skip: server.isEmpty
        ? 'set LOGOS_ACCOUNT_TEST_URL to a disposable backend'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

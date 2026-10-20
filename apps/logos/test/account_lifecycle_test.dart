import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/account_remote.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/state/account_manager.dart';
import 'support/account_support.dart';

class FailingGuestClear extends LocalStore {
  FailingGuestClear(super.executor);
  bool fail = true;
  @override
  Future<void> clearGuestBusiness() async {
    if (fail) {
      fail = false;
      throw StateError('转移后清理中断');
    }
    await super.clearGuestBusiness();
  }
}

class FailingAdoption extends LocalStore {
  FailingAdoption(super.executor);
  @override
  Future<void> adoptGuest(StoreSnapshot source, String id) async {
    throw StateError('目标库暂时不可写');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AccountTestRig rig;
  late AccountManager manager;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('logos-accounts-');
    rig = AccountTestRig(directory, MemoryCredentials(), FakeAccountRemote());
    manager = rig.manager();
  });
  tearDown(() async {
    await manager.close();
    manager.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'guest ownership transfers all content and revisions to A; logout and B remain isolated',
    () async {
      await addTestNote(manager.guest, 'guest-note');
      final revision = (await manager.guest.pendingChanges()).single.revision;
      await manager.guest.setSetting(
        'lastPosition',
        '{"bookCode":"JOHN","chapter":3,"verse":16}',
      );
      await manager.guest.setSetting('searchHistory', '["神爱世人"]');
      await manager.guest.setSetting('device.bin', 'encrypted-device-cache');
      await connectTestAccount(manager);
      expect((await manager.store.list('note')).single['id'], 'guest-note');
      expect((await manager.store.pendingChanges()).single.revision, revision);
      expect(await manager.guest.list('note'), isEmpty);
      expect(await manager.guest.pendingCount(), 0);
      expect(await manager.store.setting('searchHistory'), '["神爱世人"]');
      await manager.logout();
      expect(await manager.store.list('note'), isEmpty);
      expect(await manager.store.setting('lastPosition'), isNull);
      expect(await manager.store.setting('searchHistory'), isNull);
      expect(
        await manager.store.setting('device.bin'),
        'encrypted-device-cache',
      );
      await connectTestAccount(manager, phone: 'B');
      expect(await manager.store.list('note'), isEmpty);
      await manager.logout();
      await connectTestAccount(manager);
      expect((await manager.store.list('note')).single['id'], 'guest-note');
      expect((await manager.store.pendingChanges()).single.revision, revision);
      final secretRows = await manager.store
          .customSelect(
            "SELECT key FROM settings WHERE value LIKE '%test-session%'",
          )
          .get();
      expect(secretRows, isEmpty);
      expect(jsonDecode(rig.credentials.value!)['userId'], '1');
    },
  );

  test(
    'transport failure persists across restart, then uploads and pulls without requeueing cloud rows',
    () async {
      await addTestNote(manager.guest, 'note');
      await connectTestAccount(manager);
      rig.remote.offline = true;
      await manager.sync();
      expect(manager.syncError, contains('离线'));
      await manager.close();
      manager.dispose();
      manager = rig.manager();
      await manager.restore(testServer);
      expect(manager.account!.userId, '1');
      expect((await manager.store.list('note')).single['content'], '个人笔记');
      expect(manager.pendingCount, 1);
      rig.remote.offline = false;
      await manager.sync();
      expect(manager.syncError, isNull);
      expect(manager.pendingCount, 0);
      expect((await manager.store.list('note')).single['tags'], ['带,逗号']);
      expect(await manager.store.pendingCount(), 0);
      expect(manager.lastSyncedAt, isNotNull);
    },
  );

  test(
    'lost response retries the identical revision payload and can finish safely',
    () async {
      await addTestNote(manager.guest, 'note');
      await connectTestAccount(manager);
      rig.remote.loseReply = true;
      await manager.sync();
      expect(await manager.store.pendingCount(), 1);
      await manager.sync();
      expect(rig.remote.requests, hasLength(2));
      expect(rig.remote.requests[0].items, rig.remote.requests[1].items);
      expect(await manager.store.pendingCount(), 0);
      expect(await manager.store.list('note'), hasLength(1));
    },
  );

  test(
    'partial failures do not starve later batches and remain local through a pull',
    () async {
      for (var i = 0; i < 105; i++) {
        await addTestNote(manager.guest, 'note-$i');
      }
      await connectTestAccount(manager);
      rig.remote.failedKeys = {'note-0'};
      await manager.sync();
      expect(rig.remote.requests, hasLength(2));
      expect((await manager.store.pendingChanges()).single.clientKey, 'note-0');
      expect(await manager.store.list('note'), hasLength(105));
      expect(manager.syncError, contains('部分数据未上传'));
      rig.remote.failedKeys.clear();
      await manager.sync();
      expect(await manager.store.pendingCount(), 0);
    },
  );

  test(
    'an edit during a cloud pull overlays that response and retains its outbox revision',
    () async {
      await addTestNote(manager.guest, 'note');
      await connectTestAccount(manager);
      rig.remote.fetchStarted = Completer<void>();
      rig.remote.fetchGate = Completer<void>();
      final syncing = manager.sync();
      await rig.remote.fetchStarted!.future;
      await manager.withStore(
        (store) => addTestNote(store, 'note', content: '拉取期间的新编辑'),
      );
      final revision = (await manager.store.pendingChanges()).single.revision;
      rig.remote.fetchGate!.complete();
      await syncing;
      expect((await manager.store.list('note')).single['content'], '拉取期间的新编辑');
      expect((await manager.store.pendingChanges()).single.revision, revision);
    },
  );

  test(
    'A late response after logout and login as B cannot acknowledge or cache data into B',
    () async {
      await addTestNote(manager.guest, 'A-note');
      await connectTestAccount(manager);
      rig.remote.uploadStarted = Completer<void>();
      rig.remote.uploadGate = Completer<void>();
      final oldSync = manager.sync();
      await rig.remote.uploadStarted!.future;
      await manager.logout();
      await connectTestAccount(manager, phone: 'B');
      await manager.withStore((store) => addTestNote(store, 'B-note'));
      rig.remote.uploadGate!.complete();
      await oldSync;
      expect((await manager.store.list('note')).single['id'], 'B-note');
      expect((await manager.store.pendingChanges()).single.clientKey, 'B-note');
      await manager.logout();
      await connectTestAccount(manager);
      expect((await manager.store.pendingChanges()).single.clientKey, 'A-note');
    },
  );

  test(
    'same user id on two services has different cache files and no shared credential routing',
    () async {
      await addTestNote(manager.guest, 'first-server');
      await connectTestAccount(manager);
      await manager.logout();
      const second = 'https://second.example/graphql';
      await connectTestAccount(manager, server: second);
      expect(manager.account!.userId, '1');
      expect(await manager.store.list('note'), isEmpty);
      expect(
        await accountDatabaseName(testServer, '1'),
        isNot(await accountDatabaseName(second, '1')),
      );
      await manager.close();
      manager.dispose();
      manager = rig.manager();
      await manager.restore(testServer);
      expect(manager.account, isNull);
      expect(manager.syncError, contains('服务地址已变化'));
      expect(rig.remote.requests, isEmpty);
    },
  );

  test(
    'failed login and an attempted direct account switch preserve the current owner',
    () async {
      await addTestNote(manager.guest, 'note');
      rig.remote.rejectLogin = true;
      await expectLater(connectTestAccount(manager), throwsStateError);
      expect(await manager.guest.list('note'), hasLength(1));
      expect(await manager.guest.setting('guestTransfer'), isNull);
      rig.remote.rejectLogin = false;
      await connectTestAccount(manager);
      await expectLater(
        connectTestAccount(manager, phone: 'B'),
        throwsStateError,
      );
      expect(manager.account!.userId, '1');
      expect(await manager.store.list('note'), hasLength(1));
    },
  );

  test(
    'interrupted destination commit quarantines guest data and recovers it to its original owner',
    () async {
      await manager.close();
      manager.dispose();
      manager = rig.manager(
        factory: (name) =>
            FailingAdoption(NativeDatabase(File('${directory.path}/$name.db'))),
      );
      await addTestNote(manager.guest, 'owned-by-A');
      await expectLater(connectTestAccount(manager), throwsStateError);
      expect(manager.guestLocked, isTrue);
      await expectLater(
        manager.withStore((store) => store.list('note')),
        throwsStateError,
      );
      await manager.close();
      manager.dispose();
      manager = rig.manager();
      await manager.restore(testServer);
      expect(manager.guestLocked, isFalse);
      expect(await manager.store.list('note'), isEmpty);
      await connectTestAccount(manager, phone: 'B');
      expect(await manager.store.list('note'), isEmpty);
      await manager.logout();
      await connectTestAccount(manager);
      expect((await manager.store.list('note')).single['id'], 'owned-by-A');
    },
  );

  test(
    'interruption after destination commit resumes without changing imported revisions',
    () async {
      await manager.close();
      manager.dispose();
      manager = rig.manager(
        guest: FailingGuestClear(
          NativeDatabase(File('${directory.path}/guest.db')),
        ),
      );
      await addTestNote(manager.guest, 'note');
      final revision = (await manager.guest.pendingChanges()).single.revision;
      await expectLater(connectTestAccount(manager), throwsStateError);
      expect(manager.guestLocked, isTrue);
      await manager.close();
      manager.dispose();
      manager = rig.manager();
      await manager.restore(testServer);
      await connectTestAccount(manager);
      expect((await manager.store.pendingChanges()).single.revision, revision);
      expect(await manager.store.list('note'), hasLength(1));
    },
  );

  test(
    'secure credential write failure preserves transferred data for A and never gives it to B',
    () async {
      await addTestNote(manager.guest, 'A-note');
      rig.credentials.failWrite = true;
      await expectLater(connectTestAccount(manager), throwsStateError);
      expect(await manager.store.list('note'), isEmpty);
      rig.credentials.failWrite = false;
      await connectTestAccount(manager, phone: 'B');
      expect(await manager.store.list('note'), isEmpty);
      await manager.logout();
      await connectTestAccount(manager);
      expect((await manager.store.list('note')).single['id'], 'A-note');
    },
  );

  test(
    'logout waits for in-flight local writes and a failed credential removal keeps the account active',
    () async {
      await connectTestAccount(manager);
      final gate = Completer<void>();
      final started = Completer<void>();
      final writing = manager.withStore((store) async {
        started.complete();
        await gate.future;
        await addTestNote(store, 'last-A-write');
      });
      await started.future;
      final logout = manager.logout();
      expect(manager.transitioning, isTrue);
      gate.complete();
      await writing;
      await logout;
      await connectTestAccount(manager);
      expect((await manager.store.list('note')).single['id'], 'last-A-write');
      rig.credentials.failClear = true;
      await expectLater(manager.logout(), throwsStateError);
      expect(manager.account!.userId, '1');
      expect(await manager.store.list('note'), hasLength(1));
    },
  );

  test(
    'expired credentials preserve account cache and edits; only reconnecting that account resumes sync',
    () async {
      await addTestNote(manager.guest, 'note');
      await connectTestAccount(manager);
      rig.remote.expired = true;
      await manager.sync();
      expect(manager.syncError, contains('已过期'));
      expect(manager.account!.userId, '1');
      expect(await manager.store.pendingCount(), 1);
      rig.remote.expired = false;
      await connectTestAccount(manager);
      await manager.sync();
      expect(manager.pendingCount, 0);
    },
  );

  test(
    'automatic retry after a connection failure sends the retained outbox',
    () async {
      await manager.close();
      manager.dispose();
      manager = rig.manager(retry: const Duration(milliseconds: 20));
      await addTestNote(manager.guest, 'note');
      await connectTestAccount(manager);
      rig.remote.offline = true;
      await manager.sync();
      rig.remote.fetched = Completer<void>();
      rig.remote.offline = false;
      await rig.remote.fetched!.future.timeout(const Duration(seconds: 5));
      await manager.sync();
      expect(manager.pendingCount, 0);
      expect(manager.syncError, isNull);
    },
  );
}

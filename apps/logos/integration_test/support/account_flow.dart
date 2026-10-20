import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:logos/data/account_remote.dart';
import 'package:logos/data/bible_models.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/main.dart' as entry;
import 'package:logos/state/account_manager.dart';
import 'package:logos/state/app_controller.dart';

/// Only the separately packaged acceptance APK reads host-controlled phases.
class AcceptanceConfig {
  AcceptanceConfig(Map<String, dynamic> json)
    : phase = json['phase'] as String,
      runId = json['runId'] as String,
      phoneA = json['phoneA'] as String,
      phoneB = json['phoneB'] as String;
  final String phase;
  final String runId;
  final String phoneA;
  final String phoneB;
}

Future<AcceptanceConfig?> readAcceptanceConfig() async {
  if (!const bool.fromEnvironment('LOGOS_ANDROID_ACCEPTANCE')) return null;
  final directory = await getApplicationSupportDirectory();
  final config = File('${directory.path}/logos-acceptance.json');
  if (!await config.exists()) {
    throw StateError('Use tools/run_android_acceptance.py to provide a phase.');
  }
  return AcceptanceConfig(jsonDecode(await config.readAsString()));
}

void reportAcceptancePhase(
  IntegrationTestWidgetsFlutterBinding binding,
  AcceptanceConfig config,
) {
  binding.reportData = {
    ...?binding.reportData,
    'acceptance': {'runId': config.runId, 'phase': config.phase, 'pid': pid},
  };
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  expect(ready(), isTrue, reason: 'Account operation did not finish');
}

Future<bool> _reachable(Uri uri) async {
  try {
    final socket = await Socket.connect(
      uri.host,
      uri.port,
      timeout: const Duration(seconds: 3),
    );
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

Future<void> _accountPage(WidgetTester tester) async {
  entry.router.go('/login');
  await _wait(tester, () => find.text('账号与同步').evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('账号与同步'), findsOneWidget);
}

Future<void> _login(
  WidgetTester tester,
  AppController app,
  String phone, {
  bool verifyConsent = false,
}) async {
  await _accountPage(tester);
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), phone);
  await tester.enterText(fields.at(1), '246810');
  await tester.enterText(fields.at(2), 'LOGOS-LOCAL');
  final button = find.text('连接开发账号并合并');
  await tester.ensureVisible(button);
  if (verifyConsent) {
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(app.accounts.account, isNull);
    expect(find.text('请先阅读并同意当前数据处理说明'), findsOneWidget);
  }
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _wait(
    tester,
    () => app.accounts.account != null && !app.accounts.transitioning,
  );
  await _wait(
    tester,
    () => find.textContaining('开发账号 ·').evaluate().isNotEmpty,
  );
  expect(find.textContaining('开发账号 ·'), findsOneWidget);
  await _accountPage(tester);
  expect(find.text('退出当前账号'), findsOneWidget);
}

Future<void> _logout(WidgetTester tester, AppController app) async {
  await _accountPage(tester);
  await tester.ensureVisible(find.text('退出当前账号'));
  await tester.tap(find.text('退出当前账号'));
  await _wait(
    tester,
    () => app.accounts.account == null && !app.accounts.transitioning,
  );
  await _wait(tester, () => find.text('游客模式 · 数据保存在此设备').evaluate().isNotEmpty);
  expect(find.text('游客模式 · 数据保存在此设备'), findsOneWidget);
  expect(app.notes, isEmpty);
  expect(app.bookmarks, isEmpty);
  expect(app.progress, isEmpty);
  expect(app.records, isEmpty);
  expect(app.searchHistory, isEmpty);
  expect(app.last.bookCode, 'GEN');
  expect(app.last.chapter, 1);
  expect(app.bible.offlineReady, isTrue);
  expect(app.dark, isTrue);
  expect(app.fontSize, 23);
  expect(await tester.runAsync(app.accounts.credentials.read), isNull);
}

Future<void> _sync(WidgetTester tester, AppController app) async {
  await tester.runAsync(app.accounts.sync);
  await _wait(tester, () => !app.accounts.syncing);
  expect(app.accounts.syncError, isNull);
  expect(app.accounts.pendingCount, 0);
  expect(app.accounts.lastSyncedAt, isNotNull);
}

Future<void> _save(AppController app, String id, String content) =>
    app.saveNote(
      id: id,
      title: id,
      content: content,
      verseIds: ['43003016', '43003017'],
      tags: ['Android验收', '含,逗号'],
    );

Map<String, dynamic> _note(AppController app, String id) =>
    app.notes.singleWhere((note) => note['id'] == id);

Future<List<String>> _pendingVersionsOf(LocalStore store) async =>
    (await store.pendingChanges())
        .map(
          (change) => '${change.kind}:${change.clientKey}:${change.revision}',
        )
        .toList()
      ..sort();

Future<List<String>> _pendingVersions(AppController app) =>
    _pendingVersionsOf(app.store);

Future<void> runAccountPhase(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  AcceptanceConfig config,
) async {
  const server = String.fromEnvironment('API_URL');
  final uri = Uri.parse(server);
  // localhost-only + removal of this exact ADB reverse makes USB testing offline
  // without disconnecting the separate VM-service control channel.
  expect(uri.host, '127.0.0.1');
  final offline = config.phase.startsWith('offline-');
  expect(await tester.runAsync(() => _reachable(uri)), !offline);
  entry.main();
  AppController? controller;
  await _wait(tester, () {
    final root = find.byType(entry.LogosApp);
    if (root.evaluate().isEmpty) return false;
    controller = ProviderScope.containerOf(
      tester.element(root),
    ).read(appProvider);
    return controller!.ready && !controller!.connecting;
  });
  final app = controller!;
  expect(app.error, isNull);
  expect(app.bible.offlineReady, isTrue);
  expect(app.bible.search('神爱世人').first.id, '43003016');
  final guestId = 'guest-${config.runId}';
  final deleteId = 'delete-${config.runId}';
  final offlineId = 'offline-${config.runId}';
  final bId = 'B-${config.runId}';
  final markerKey = 'acceptance-${config.runId}';

  if (config.phase == 'seed') {
    expect(app.accounts.account, isNull);
    await tester.runAsync(() async {
      await app.theme(true);
      await app.typography(23, 1.9);
      await _save(app, guestId, 'guest content');
      await _save(app, deleteId, 'delete after disconnect');
      await app.bookmark(app.bible.byId['43003017']!);
      await app.recordPosition(const ChapterPosition('JOHN', 3, verse: 17));
      await app.addSearch('神爱世人');
      await app.store.addFeed({
        'id': 'share-${config.runId}',
        'type': 'SCRIPTURE_SHARED',
        'content': 'Synthetic multi-verse share; no external app is opened.',
        'verseIds': ['43003016', '43003017'],
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      await app.refresh();
    });
    await _login(tester, app, config.phoneA, verifyConsent: true);
    await _sync(tester, app);
    final a = app.accounts.account!;
    expect(_note(app, guestId)['verseIds'], ['43003016', '43003017']);
    expect(
      await tester.runAsync(() => app.accounts.guest.list('note')),
      isEmpty,
    );
    await _logout(tester, app);
    await _login(tester, app, config.phoneB);
    await _sync(tester, app);
    expect(app.accounts.account!.userId, isNot(a.userId));
    expect(app.notes, isEmpty);
    expect(app.bookmarks, isEmpty);
    await tester.runAsync(() => _save(app, bId, 'only B'));
    await _sync(tester, app);
    await _logout(tester, app);
    await _login(tester, app, config.phoneA);
    await _sync(tester, app);
    expect(app.accounts.account!.userId, a.userId);
    expect(app.notes.any((note) => note['id'] == bId), isFalse);
    expect(_note(app, guestId)['content'], 'guest content');
    await tester.runAsync(
      () => app.accounts.guest.setSetting(
        markerKey,
        jsonEncode({'userId': a.userId}),
      ),
    );
  } else {
    final savedMarker = await tester.runAsync<String?>(
      () => app.accounts.guest.setting(markerKey),
    );
    final marker = jsonDecode(savedMarker!) as Map<String, dynamic>;
    if (config.phase != 'reconnect') {
      expect(app.accounts.account?.userId, marker['userId']);
    }
    expect(app.dark, isTrue);
    expect(app.fontSize, 23);
    expect(app.notes.any((note) => note['id'] == bId), isFalse);
    if (config.phase == 'offline-write') {
      expect(_note(app, guestId)['content'], 'guest content');
      await tester.runAsync(() async {
        await _save(app, guestId, 'offline update');
        await _save(app, offlineId, 'offline new');
        await app.removeNote(deleteId);
        await app.removeBookmark('43003017');
        await app.accounts.sync();
        expect(app.accounts.syncError, isNotNull);
        expect(app.accounts.pendingCount, greaterThanOrEqualTo(4));
        await app.accounts.guest.setSetting(
          markerKey,
          jsonEncode({...marker, 'pending': await _pendingVersions(app)}),
        );
      });
    } else if (config.phase == 'offline-reopen') {
      expect(_note(app, guestId)['content'], 'offline update');
      expect(_note(app, offlineId)['content'], 'offline new');
      expect(app.notes.any((note) => note['id'] == deleteId), isFalse);
      expect(app.bookmarkFor('43003017'), isNull);
      expect(
        await tester.runAsync(() => _pendingVersions(app)),
        marker['pending'],
      );
      await tester.runAsync(app.accounts.sync);
      expect(app.accounts.syncError, isNotNull);
      expect(
        await tester.runAsync(() => _pendingVersions(app)),
        marker['pending'],
      );
      final aStoreName = await tester.runAsync(
        () => accountDatabaseName(server, marker['userId'] as String),
      );
      await _logout(tester, app);
      await tester.runAsync(() async {
        final retained = app.accounts.openStore(aStoreName!);
        try {
          expect(await _pendingVersionsOf(retained), marker['pending']);
          expect(
            (await retained.list('note')).any((n) => n['id'] == offlineId),
            isTrue,
          );
        } finally {
          await retained.close();
        }
      });
    } else if (config.phase == 'reconnect') {
      expect(app.accounts.account, isNull);
      await _login(tester, app, config.phoneB);
      await _sync(tester, app);
      expect(app.notes.map((n) => n['id']), [bId]);
      await _logout(tester, app);
      await _login(tester, app, config.phoneA);
      expect(app.accounts.account!.userId, marker['userId']);
      await _sync(tester, app);
      // A completely empty second set of native SQLite files proves a server
      // pull, rather than re-reading the original account's local cache.
      final probe = AccountManager(
        guest: LocalStore.named('pull_probe_guest'),
        openStore: (name) => LocalStore.named('pull_probe_$name'),
      )..referenceForId = app.bible.referenceForId;
      await tester.runAsync(() async {
        try {
          await probe.restore(server); // Real Android secure storage.
          expect(await probe.store.list('note'), isEmpty);
          await probe.sync();
          expect(probe.syncError, isNull);
          final notes = await probe.store.list('note');
          expect(
            notes.singleWhere((n) => n['id'] == guestId)['content'],
            'offline update',
          );
          expect(notes.singleWhere((n) => n['id'] == guestId)['verseIds'], [
            '43003016',
            '43003017',
          ]);
          expect(
            notes.singleWhere((n) => n['id'] == offlineId)['content'],
            'offline new',
          );
          expect(
            notes.any((n) => n['id'] == deleteId || n['id'] == bId),
            isFalse,
          );
          expect(
            (await probe.store.list(
              'bookmark',
            )).any((b) => b['id'] == '43003017'),
            isFalse,
          );
          expect(
            (await probe.store.feed()).singleWhere(
              (r) => r['id'] == 'share-${config.runId}',
            )['verseIds'],
            ['43003016', '43003017'],
          );
          await app.accounts.sync();
          await app.accounts.sync();
          expect(app.accounts.syncError, isNull);
          final cloud = await app.accounts.remote.fetch(app.accounts.account!);
          expect(
            cloud.data['note']!.where((n) => n['id'] == guestId),
            hasLength(1),
          );
          expect(
            cloud.data['note']!.where((n) => n['id'] == offlineId),
            hasLength(1),
          );
          expect(
            cloud.records.where((r) => r['id'] == 'share-${config.runId}'),
            hasLength(1),
          );
        } finally {
          await probe.close();
          probe.dispose();
        }
      });
    } else {
      fail('Unknown host acceptance phase: ${config.phase}');
    }
  }
  expect(tester.takeException(), isNull);
  reportAcceptancePhase(binding, config);
}

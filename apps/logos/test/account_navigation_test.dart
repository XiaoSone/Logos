import 'dart:io';
import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/bible_models.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/main.dart' as product;
import 'package:logos/state/account_manager.dart';
import 'package:logos/state/app_controller.dart';
import 'support/account_support.dart';

class AccountUiController extends AppController {
  AccountUiController(AccountManager accounts) : super(accounts: accounts);
  @override
  Future<void> boot() async {}
}

class SettingReadGate {
  bool enabled = false;
  final started = Completer<void>();
  final release = Completer<void>();
}

class DelayedSettingsStore extends LocalStore {
  DelayedSettingsStore(super.executor, this.gate);
  final SettingReadGate gate;
  @override
  Future<String?> setting(String key) async {
    final value = await super.setting(key);
    if (gate.enabled && key == 'searchHistory') {
      if (!gate.started.isCompleted) gate.started.complete();
      await gate.release.future;
    }
    return value;
  }
}

void main() {
  late Directory directory;
  late AccountTestRig rig;
  late AccountUiController app;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('logos-account-ui-');
    rig = AccountTestRig(directory, MemoryCredentials(), FakeAccountRemote());
    app = AccountUiController(rig.manager())..ready = true;
    app.bible.server = testServer;
    app.bible.deviceId = 'test-device';
    product.router.go('/login');
  });
  tearDown(() async {
    await app.accounts.close();
    app.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((_) => app)],
        child: const product.LogosApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'connection describes upload consent, then switches to account status and logout resets navigation',
    (tester) async {
      try {
        await addTestNote(app.store, 'guest-note');
        await app.refresh();
        await open(tester);
        expect(find.textContaining('合并到所选账号'), findsOneWidget);
        await tester.ensureVisible(find.text('连接开发账号并合并'));
        await tester.tap(find.text('连接开发账号并合并'));
        await tester.pumpAndSettle();
        expect(app.accounts.account, isNull);
        expect(find.text('请先阅读并同意当前数据处理说明'), findsOneWidget);
        await tester.enterText(find.byType(TextField).at(0), 'A');
        await tester.enterText(find.byType(TextField).at(1), 'test');
        await tester.enterText(find.byType(TextField).at(2), 'test');
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.ensureVisible(find.text('连接开发账号并合并'));
        await tester.tap(find.text('连接开发账号并合并'));
        await tester.pumpAndSettle();
        expect(product.router.routeInformationProvider.value.uri.path, '/mine');
        expect(app.accounts.account!.userId, '1');
        expect(app.notes, hasLength(1));
        await tester.tap(find.byTooltip('登录信息'));
        await tester.pumpAndSettle();
        expect(find.text('账号与同步'), findsOneWidget);
        expect(find.text('退出当前账号'), findsOneWidget);
        await tester.tap(find.text('退出当前账号'));
        await tester.pumpAndSettle();
        expect(product.router.routeInformationProvider.value.uri.path, '/mine');
        expect(app.accounts.account, isNull);
        expect(app.notes, isEmpty);
        expect(find.text('游客模式 · 数据保存在此设备'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.runAsync(app.accounts.close);
      }
    },
  );

  testWidgets(
    'a draft opened for A cannot save into B after account scope changes',
    (tester) async {
      try {
        await connectTestAccount(app.accounts);
        await app.refresh();
        product.router.go('/note/new');
        await open(tester);
        await tester.enterText(find.byType(TextField).at(0), 'A 的草稿');
        await tester.enterText(find.byType(TextField).at(1), '不能进入 B');
        await tester.runAsync(() async {
          await app.logout();
          await connectTestAccount(app.accounts, phone: 'B');
          await app.refresh();
        });
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(find.text('账号已变化，请返回当前账号重新打开笔记'), findsOneWidget);
        expect(app.notes, isEmpty);
        expect(await app.store.pendingCount(), 0);
      } finally {
        await tester.runAsync(app.accounts.close);
      }
    },
  );

  test(
    'sync snapshots refresh visible account data without reopening or manual refresh',
    () async {
      rig.remote.rows['$testServer:1'] = {
        'NOTE:cloud-note': {
          'id': 'cloud-note',
          'title': '另一台设备的笔记',
          'content': '云端第一版',
          'verseIds': ['43003016', '43003017'],
          'tags': ['同步'],
          'createdAt': testTime,
          'updatedAt': testTime,
        },
      };
      await app.login(phone: 'A', code: 'test', invite: 'test');
      expect(app.notes, isEmpty);
      await app.accounts.sync();
      expect(app.accounts.syncError, isNull);
      expect(app.notes.single['content'], '云端第一版');
      rig.remote.rows['$testServer:1']!['NOTE:cloud-note']!['content'] =
          '云端第二版';
      await app.accounts.sync();
      expect(app.notes.single['content'], '云端第二版');
      await app.logout();
      expect(app.notes, isEmpty);
    },
  );

  test(
    'signed-in service changes are rejected and logout clears memory and personal positions',
    () async {
      await connectTestAccount(app.accounts);
      app.last = const ChapterPosition('JOHN', 3, verse: 16);
      app.searchHistory = ['原账号搜索'];
      await expectLater(
        app.setServer('https://different.example/graphql'),
        throwsArgumentError,
      );
      expect(app.bible.server, testServer);
      await app.logout();
      expect(app.searchHistory, isEmpty);
      expect(app.last.bookCode, 'GEN');
    },
  );

  test(
    'logout waits for a pending personal-settings reload and clears the former account from memory',
    () async {
      await app.accounts.close();
      app.dispose();
      final gate = SettingReadGate();
      app = AccountUiController(
        rig.manager(
          factory: (name) => DelayedSettingsStore(
            NativeDatabase(File('${directory.path}/$name.db')),
            gate,
          ),
        ),
      )..ready = true;
      app.bible.server = testServer;
      app.bible.deviceId = 'test-device';
      await app.login(phone: 'A', code: 'test', invite: 'test');
      await app.accounts.withStore((store) async {
        await store.setSetting('searchHistory', '["仅 A 的搜索"]');
        await store.setSetting(
          'lastPosition',
          '{"bookCode":"JOHN","chapter":3,"verse":16}',
        );
      });
      gate.enabled = true;
      app.searchHistory = ['A 内存中的搜索'];
      final loading = app.login(phone: 'A', code: 'test', invite: 'test');
      await gate.started.future;
      final exiting = app.logout();
      expect(app.accounts.transitioning, isTrue);
      expect(app.searchHistory, isEmpty);
      gate.release.complete();
      await loading;
      await exiting;
      expect(app.accounts.account, isNull);
      expect(app.searchHistory, isEmpty);
      expect(app.last.bookCode, 'GEN');
      expect(app.notes, isEmpty);
    },
  );
}

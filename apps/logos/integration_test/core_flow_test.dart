import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logos/main.dart' as entry;
import 'package:logos/state/app_controller.dart';
import 'package:logos/data/bible_repository.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/ui/scripture_text.dart';
import 'support/account_flow.dart';

Future<void> waitUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  expect(ready(), isTrue, reason: 'Async UI operation did not finish in 20s');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('read, search, highlight, note and encrypted offline restore', (
    tester,
  ) async {
    final config = await tester.runAsync(readAcceptanceConfig);
    if (config != null && config.phase != 'core') {
      await runAccountPhase(tester, binding, config);
      return;
    }
    entry.main();
    AppController? controller;
    for (var i = 0; i < 240; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 250));
      final root = find.byType(entry.LogosApp);
      if (root.evaluate().isNotEmpty) {
        final candidate = ProviderScope.containerOf(
          tester.element(root),
        ).read(appProvider);
        controller = candidate;
        if (candidate.ready &&
            candidate.bible.unlocked &&
            !candidate.connecting) {
          break;
        }
      }
    }
    expect(controller, isNotNull);
    final app = controller!;
    final noteTitle = '本机验收笔记 ${DateTime.now().microsecondsSinceEpoch}';
    expect(app.error, isNull);
    expect(app.bible.unlocked, isTrue, reason: app.connectionError);
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('logos-home-android');
    await tester.tap(find.text('搜索经文或引用，如「约 3:16」'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '神爱世人');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await waitUntil(tester, () => find.text('1 条结果').evaluate().isNotEmpty);
    expect(find.text('1 条结果'), findsOneWidget);
    await tester.tap(find.text('约翰福音 3:16'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('logos-reader-android');
    final verse = app.bible.byId['43003016']!;
    final paragraph = tester
        .stateList<ScriptureParagraphState>(find.byType(ScriptureParagraph))
        .firstWhere(
          (state) => state.widget.verses.any((v) => v.id == verse.id),
        );
    await tester.tapAt(paragraph.versePoint(verse.id)! + const Offset(3, 8));
    await tester.pumpAndSettle();
    await tester.longPressAt(
      paragraph.versePoint(verse.id)! + const Offset(3, 8),
    );
    await tester.pumpAndSettle();
    await waitUntil(
      tester,
      () => find.bySemanticsLabel('高亮颜色 #F2D893').evaluate().isNotEmpty,
    );
    await tester.tap(find.bySemanticsLabel('高亮颜色 #F2D893'));
    await tester.pumpAndSettle();
    await waitUntil(
      tester,
      () => app.bookmarkFor(verse.id)?['color'] == '#F2D893',
    );
    expect(app.bookmarkFor(verse.id)?['color'], '#F2D893');
    await tester.longPressAt(
      paragraph.versePoint(verse.id)! + const Offset(3, 8),
    );
    await tester.pumpAndSettle();
    await waitUntil(tester, () => find.text('笔记').evaluate().isNotEmpty);
    await tester.tap(find.text('笔记').last);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), noteTitle);
    await tester.enterText(fields.at(1), '验证经文关联、事务保存与离线恢复。');
    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), '验收，读经');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await waitUntil(
      tester,
      () =>
          app.notes.any((n) => n['title'] == noteTitle) &&
          app.records.any((r) => r['type'] == 'NOTE_CREATED'),
    );
    expect(
      app.notes.any(
        (n) =>
            n['title'] == noteTitle &&
            (n['verseIds'] as List).contains(verse.id),
      ),
      isTrue,
    );
    expect(
      app.records.any(
        (r) => r['type'] == 'SCRIPTURE_HIGHLIGHT' && r['verseId'] == verse.id,
      ),
      isTrue,
    );
    expect(app.records.any((r) => r['type'] == 'NOTE_CREATED'), isTrue);
    await tester.runAsync(() => app.bible.download());
    expect(app.bible.offlineReady, isTrue);
    final freshStore = LocalStore();
    try {
      final fresh = BibleRepository(freshStore);
      // initialize has no HTTP operation; connect is deliberately never called.
      await tester.runAsync(fresh.initialize);
      expect(fresh.offlineReady, isTrue);
      expect(fresh.search('神爱世人').first.id, verse.id);
      expect(
        (await tester.runAsync(
          () => freshStore.list('note'),
        ))!.any((n) => n['title'] == noteTitle),
        isTrue,
      );
    } finally {
      await tester.runAsync(freshStore.close);
    }
    expect(tester.takeException(), isNull);
    if (config != null) reportAcceptancePhase(binding, config);
  });
}

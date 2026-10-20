import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logos/data/bible_models.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/state/app_controller.dart';
import 'package:logos/ui/catalog_page.dart';
import 'package:logos/ui/design.dart';
import 'package:logos/ui/library_pages.dart';

class ReferenceTestController extends AppController {
  ReferenceTestController() : super(store: LocalStore(NativeDatabase.memory()));
  final saved = Completer<void>();
  @override
  Future<void> boot() async {}
  @override
  Future<void> saveNote({
    String? id,
    required String title,
    required String content,
    required List<String> verseIds,
    required List<String> tags,
  }) async {
    await super.saveNote(
      id: id,
      title: title,
      content: content,
      verseIds: verseIds,
      tags: tags,
    );
    if (!saved.isCompleted) saved.complete();
  }
}

void main() {
  late ReferenceTestController app;
  late GoRouter router;
  setUp(() {
    app = ReferenceTestController();
    app.bible.books = [
      const Book({
        'bookCode': 'GEN',
        'bookNameZh': '创世记',
        'bookNameAbbr': '创',
        'bookNameEn': 'Genesis',
        'bookOrder': 1,
        'chapterCount': 2,
        'testament': 1,
        'aliases': ['GEN', '创'],
      }),
      const Book({
        'bookCode': 'JOHN',
        'bookNameZh': '约翰福音',
        'bookNameAbbr': '约',
        'bookNameEn': 'John',
        'bookOrder': 43,
        'chapterCount': 1,
        'testament': 2,
        'aliases': ['JOHN', '约'],
      }),
    ];
    app.bible.verses = [
      for (final number in [1, 2, 3])
        Verse({
          'id': 'GEN.1.$number',
          'bookCode': 'GEN',
          'chapter': 1,
          'verse': number,
          'textZh': '第一章经文 $number',
        }),
      for (final number in [1, 2])
        Verse({
          'id': 'GEN.2.$number',
          'bookCode': 'GEN',
          'chapter': 2,
          'verse': number,
          'bridgeStart': 1,
          'verseLabel': '1-2',
          'textZh': '第二章合节正文',
        }),
      for (final number in [1, 2])
        Verse({
          'id': 'JOHN.1.$number',
          'bookCode': 'JOHN',
          'chapter': 1,
          'verse': number,
          'textZh': '新约经文 $number',
        }),
    ];
    app.bible.byId = {for (final verse in app.bible.verses) verse.id: verse};
    app.bible.byChapter = {
      for (final key in ['GEN.1', 'GEN.2', 'JOHN.1'])
        key: app.bible.verses
            .where((verse) => '${verse.bookCode}.${verse.chapter}' == key)
            .toList(),
    };
    router = GoRouter(
      initialLocation: '/note/new',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('测试首页')),
        ),
        GoRoute(path: '/note/new', builder: (_, _) => const NoteEditor()),
        GoRoute(
          path: '/note/:id',
          builder: (_, state) => NoteEditor(id: state.pathParameters['id']),
        ),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    await app.store.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((_) => app)],
        child: MaterialApp.router(
          theme: logosTheme(false),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder verse(String id) => find.byKey(ValueKey('note-reference-$id'));

  testWidgets(
    'book chapter verse picker retains cross-book selections and saves the note draft',
    (tester) async {
      await open(tester);
      final title = tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
      final body = tester
          .widget<TextField>(find.byType(TextField).at(1))
          .controller!;
      await tester.enterText(find.byType(TextField).first, '未保存的标题');
      await tester.enterText(find.byType(TextField).at(1), '未保存的笔记正文');
      await tap(tester, find.text('添加'));
      expect(find.text('添加经文'), findsOneWidget);
      expect(find.text('目录到节'), findsNothing);
      expect(find.text('和合本'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (tester.widget<GridView>(find.byType(GridView).first).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        4,
      );
      await tap(tester, find.text('创世记'));
      expect(
        (tester.widget<GridView>(find.byType(GridView)).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        5,
      );
      await tap(tester, find.text('1'));
      await tap(tester, verse('GEN.1.1'));
      await tap(tester, verse('GEN.1.3'));
      expect(find.byType(CatalogPage), findsOneWidget);
      await tap(tester, find.text('章'));
      await tap(tester, find.text('2'));
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tap(tester, verse('GEN.2.1'));
      await tap(tester, find.text('卷'));
      await tap(tester, find.widgetWithText(TextButton, '新约'));
      await tap(tester, find.text('约翰福音'));
      await tap(tester, find.text('1'));
      await tap(tester, verse('JOHN.1.2'));
      await tap(tester, find.text('确定'));
      expect(find.byType(CatalogPage), findsNothing);
      expect(title.text, '未保存的标题');
      expect(body.text, '未保存的笔记正文');
      expect(find.text('创2:1-2　第二章合节正文'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('保存'));
        await app.saved.future;
      });
      await tester.pumpAndSettle();
      expect(app.notes.single['verseIds'], [
        'GEN.1.1',
        'GEN.1.3',
        'GEN.2.1',
        'GEN.2.2',
        'JOHN.1.2',
      ]);
      expect(app.notes.single['title'], '未保存的标题');
      expect(app.records.single['type'], 'NOTE_CREATED');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing references are checked and back discards only the picker changes',
    (tester) async {
      app.notes = [
        {
          'id': 'existing',
          'title': '原有标题',
          'content': '原有正文',
          'tags': ['读经'],
          'verseIds': ['GEN.1.1', 'JOHN.1.1'],
        },
      ];
      await open(tester);
      router.go('/note/existing');
      await tester.pumpAndSettle();
      final body = tester
          .widget<TextField>(find.byType(TextField).at(1))
          .controller!;
      await tester.enterText(find.byType(TextField).at(1), '正在编辑尚未保存');
      await tap(tester, find.text('添加'));
      await tap(tester, find.text('创世记'));
      await tap(tester, find.text('1'));
      expect(tester.widget<CheckboxListTile>(verse('GEN.1.1')).value, isTrue);
      await tap(tester, verse('GEN.1.1'));
      await tap(tester, verse('GEN.1.2'));
      await tap(tester, find.text('返回'));
      expect(body.text, '正在编辑尚未保存');
      expect(find.text('创1:1　第一章经文 1'), findsOneWidget);
      expect(find.text('创1:2　第一章经文 2'), findsNothing);
      await tap(tester, find.text('添加'));
      await tap(tester, find.text('创世记'));
      await tap(tester, find.text('1'));
      expect(tester.widget<CheckboxListTile>(verse('GEN.1.1')).value, isTrue);
      expect(tester.widget<CheckboxListTile>(verse('GEN.1.2')).value, isFalse);
      await tap(tester, verse('GEN.1.1'));
      await tap(tester, verse('GEN.1.2'));
      await tap(tester, find.text('确定'));
      expect(find.text('创1:1　第一章经文 1'), findsNothing);
      expect(find.text('创1:2　第一章经文 2'), findsOneWidget);
      expect(find.text('约1:1　新约经文 1'), findsOneWidget);
      expect(app.notes.single['verseIds'], ['GEN.1.1', 'JOHN.1.1']);
      expect(body.text, '正在编辑尚未保存');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection limit rejects additions and merged groups without truncating existing choices',
    (tester) async {
      await open(tester);
      List<String>? result;
      Navigator.of(tester.element(find.byType(NoteEditor)))
          .push<List<String>>(
            MaterialPageRoute(
              builder: (_) => const CatalogPage(
                selectVerses: true,
                maxSelection: 2,
                initialVerseIds: ['GEN.1.1'],
              ),
            ),
          )
          .then((value) => result = value);
      await tester.pumpAndSettle();
      await tap(tester, find.text('创世记'));
      await tap(tester, find.text('1'));
      await tap(tester, verse('GEN.1.3'));
      await tap(tester, verse('GEN.1.2'));
      expect(tester.widget<CheckboxListTile>(verse('GEN.1.2')).value, isFalse);
      expect(find.text('最多可关联 2 节经文'), findsOneWidget);
      await tap(tester, find.text('章'));
      await tap(tester, find.text('2'));
      await tap(tester, verse('GEN.2.1'));
      expect(tester.widget<CheckboxListTile>(verse('GEN.2.1')).value, isFalse);
      await tap(tester, find.text('确定'));
      expect(result, ['GEN.1.1', 'GEN.1.3']);
      expect(tester.takeException(), isNull);
    },
  );
}

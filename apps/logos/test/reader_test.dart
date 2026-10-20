import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logos/data/bible_models.dart';
import 'package:logos/state/app_controller.dart';
import 'package:logos/ui/design.dart';
import 'package:logos/ui/reader.dart';
import 'package:logos/ui/scripture_text.dart';
import 'package:logos/ui/catalog_page.dart';
import 'package:logos/ui/library_pages.dart';
import 'package:logos/ui/reading_style.dart';

class ReaderTestController extends AppController {
  final shares = <List<Verse>>[];
  bool shareAccepted = true;

  @override
  Future<void> boot() async {}

  @override
  Future<bool> shareVerses(List<Verse> verses) async {
    shares.add(List.of(verses));
    return shareAccepted;
  }

  @override
  Future<void> recordPosition(ChapterPosition position) async =>
      last = position;

  @override
  Future<void> bookmark(Verse verse, {String? color, String? note}) async {
    bookmarks.removeWhere((bookmark) => bookmark['verseId'] == verse.id);
    bookmarks.add({'verseId': verse.id, 'color': color});
    notifyListeners();
  }

  @override
  Future<void> removeBookmark(String id) async {
    bookmarks.removeWhere((bookmark) => bookmark['verseId'] == id);
    notifyListeners();
  }

  @override
  Future<void> clearHighlight(Verse verse) async {
    if (noteCountFor(verse.id) == 0) {
      await removeBookmark(verse.id);
    } else {
      bookmarkFor(verse.id)!['color'] = null;
      notifyListeners();
    }
  }
}

Offset versePoint(WidgetTester tester, Verse verse) {
  for (final state in tester.stateList<ScriptureParagraphState>(
    find.byType(ScriptureParagraph),
  )) {
    final point = state.versePoint(verse.id);
    if (point != null) return point + const Offset(3, 8);
  }
  throw StateError('Verse ${verse.id} is not laid out');
}

TextStyle verseStyle(WidgetTester tester, Verse verse) {
  final recognizer = tester
      .stateList<ScriptureParagraphState>(find.byType(ScriptureParagraph))
      .map((state) => state.taps[verse.id])
      .where((tap) => tap != null)
      .first;
  for (final rich in tester.widgetList<RichText>(
    find.descendant(
      of: find.byType(ScriptureParagraph),
      matching: find.byType(RichText),
    ),
  )) {
    TextStyle? result;
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text != null &&
          span.text!.isNotEmpty &&
          span.recognizer == recognizer &&
          span.style?.decoration != null) {
        result = span.style;
      }
      return true;
    });
    if (result != null) return result!;
  }
  throw StateError('Missing verse style');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const font = String.fromEnvironment('LOGOS_READER_FONT');
    if (font.isNotEmpty) {
      await (FontLoader(
        'sans-serif',
      )..addFont(File(font).readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  late ReaderTestController app;
  late GoRouter router;
  late List<Verse> verses;
  final toolbar = find.byKey(const ValueKey('reader-selection-toolbar'));

  setUp(() {
    app = ReaderTestController();
    verses = [
      for (var i = 1; i <= 3; i++)
        Verse({
          'id': '$i',
          'bookCode': 'GEN',
          'chapter': 1,
          'verse': i,
          'textZh': '第 $i 节经文，用于验证长按选中。',
          'verseRef': 'GEN 1:$i',
          'sectionId': 'GEN.1',
        }),
      const Verse({
        'id': '4',
        'bookCode': 'GEN',
        'chapter': 2,
        'verse': 1,
        'textZh': '第二章的经文。',
        'verseRef': 'GEN 2:1',
        'sectionId': 'GEN.2',
      }),
    ];
    app.bible.books = [
      const Book({
        'bookCode': 'GEN',
        'bookNameZh': '创世记',
        'bookNameAbbr': '创',
        'bookNameEn': 'Genesis',
        'chapterCount': 2,
        'bookOrder': 1,
        'testament': 1,
        'aliases': ['GEN', '创世记', '创'],
      }),
    ];
    app.bible.positions = [
      const ChapterPosition('GEN', 1),
      const ChapterPosition('GEN', 2),
    ];
    app.bible.verses = verses;
    app.bible.byId = {for (final verse in verses) verse.id: verse};
    app.bible.byChapter = {
      'GEN.1': verses.take(3).toList(),
      'GEN.2': [verses.last],
    };
    app.bible.chapterIndex = [
      {'bookCode': 'GEN', 'chapter': 1, 'verseCount': 3},
      {'bookCode': 'GEN', 'chapter': 2, 'verseCount': 1},
    ];
    router = GoRouter(
      initialLocation: '/read',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('测试首页')),
        ),
        GoRoute(
          path: '/reference/:verse',
          builder: (_, state) => ReaderPage(
            bookCode: 'GEN',
            chapter: 1,
            verse: int.parse(state.pathParameters['verse']!),
          ),
        ),
        GoRoute(
          path: '/target',
          builder: (_, _) =>
              const ReaderPage(bookCode: 'GEN', chapter: 1, verse: 16),
        ),
        GoRoute(path: '/catalog', builder: (_, _) => const CatalogPage()),
        GoRoute(path: '/shares', builder: (_, _) => const SharesPage()),
        GoRoute(
          path: '/read/:book/:chapter',
          builder: (_, state) => Scaffold(
            body: Text(
              '目录选择 ${state.pathParameters['book']} ${state.pathParameters['chapter']}:${state.uri.queryParameters['verse']}',
            ),
          ),
        ),
        GoRoute(
          path: '/read',
          builder: (_, _) => const ReaderPage(bookCode: 'GEN', chapter: 1),
        ),
        GoRoute(
          path: '/note/new',
          builder: (_, state) => Scaffold(
            body: Text('笔记引用 ${state.uri.queryParameters['verses']}'),
          ),
        ),
        GoRoute(
          path: '/note/:id',
          builder: (_, state) =>
              Scaffold(body: Text('编辑测试笔记 ${state.pathParameters['id']}')),
        ),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    await app.store.close();
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    bool fullscreen = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => app)],
        child: MaterialApp.router(
          theme: logosTheme(false),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (fullscreen) {
      await tester.tapAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'tap toggles fullscreen; back exits reading and restores system UI with or without a previous route',
    (tester) async {
      await open(tester);
      final systemModes = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            systemModes.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      expect(find.text('上一章'), findsNothing);
      expect(find.text('下一章'), findsNothing);
      await tester.tapAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('目录'), findsNothing);
      expect(find.textContaining('创世记    1'), findsOneWidget);
      expect(find.text('和合本'), findsOneWidget);
      expect(toolbar, findsNothing);
      expect(app.records, isEmpty);
      await tester.tapAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      // A blank part of the reading surface uses the same fullscreen gesture.
      await tester.tapAt(const Offset(390, 450));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsNothing);
      expect(find.text('测试首页'), findsOneWidget);
      expect(systemModes.last, 'SystemUiMode.edgeToEdge');
      router.push('/read');
      await tester.pumpAndSettle();
      await tester.tapAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsNothing);
      expect(find.text('测试首页'), findsOneWidget);
      expect(systemModes.last, 'SystemUiMode.edgeToEdge');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long press selects, taps toggle additional verses, copy uses scripture order',
    (tester) async {
      await open(tester, fullscreen: true);
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.longPressAt(versePoint(tester, verses[1]));
      await tester.pumpAndSettle();
      expect(toolbar, findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(app.records, isEmpty);
      await tester.tapAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 节'), findsOneWidget);
      final style = verseStyle(tester, verses.first);
      expect(style.decoration, TextDecoration.underline);
      expect(style.decorationStyle, TextDecorationStyle.dashed);
      expect(find.byIcon(Icons.check_box), findsNothing);
      // The toolbar floats above the reader with space around its edges.
      expect(tester.getRect(toolbar).left, greaterThan(0));
      expect(tester.getRect(toolbar).right, lessThan(400));
      await tester.tapAt(versePoint(tester, verses[1]));
      await tester.pumpAndSettle();
      expect(verseStyle(tester, verses[1]).decoration, TextDecoration.none);
      await tester.tapAt(versePoint(tester, verses[1]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(copiedText, verses.take(2).map(app.bible.copyText).join('\n'));
      expect(toolbar, findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(app.records, isEmpty);
    },
  );

  testWidgets(
    'selection works in fullscreen and back cancels it before leaving reading',
    (tester) async {
      await open(tester, size: const Size(360, 800));
      await tester.tapAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      await tester.longPressAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(toolbar, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing);
      expect(find.byType(AppBar), findsNothing);
      await tester.longPressAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('高亮颜色 #F2D893'));
      await tester.pumpAndSettle();
      expect(app.bookmarkFor('1')!['color'], '#F2D893');
      expect(toolbar, findsNothing);
      expect(find.byType(AppBar), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsNothing);
      expect(find.text('测试首页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notes receive all selected references; paging clears selection',
    (tester) async {
      await open(tester, fullscreen: true);
      await tester.longPressAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      await tester.tapAt(versePoint(tester, verses[1]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('笔记'));
      await tester.pumpAndSettle();
      expect(find.text('笔记引用 1,2'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing);
      await tester.tapAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      await tester.longPressAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-360, 0));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(verses.last.text, findRichText: true),
        findsOneWidget,
      );
      expect(toolbar, findsNothing);
      expect(app.last.chapter, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('catalog grid and list navigate book, chapter and verse', (
    tester,
  ) async {
    await open(tester);
    router.go('/catalog');
    await tester.pumpAndSettle();
    expect(find.text('圣经目录'), findsOneWidget);
    expect(find.text('目录到节'), findsOneWidget);
    final grid = tester.widget<GridView>(find.byType(GridView).first);
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      4,
    );
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    await tester.tap(find.text('创世记'));
    await tester.pumpAndSettle();
    expect(find.text('目录到节'), findsNothing);
    expect(find.text('视图'), findsNothing);
    expect(find.text('旧约'), findsNothing);
    expect(find.text('新约'), findsNothing);
    expect(find.text('阅读整章'), findsNothing);
    final chapters = tester.widget<GridView>(find.byType(GridView));
    expect(
      (chapters.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      5,
    );
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.text('创世记 2'), findsOneWidget);
    final verseGrid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (verseGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      5,
    );
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('目录选择 GEN 2:1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'catalog can open a chapter directly when verse navigation is off',
    (tester) async {
      await open(tester);
      router.go('/catalog');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('创世记'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      expect(find.text('目录选择 GEN 1:1'), findsOneWidget);
    },
  );

  testWidgets(
    'a reference inside a long paragraph scrolls to its verse and remains selectable',
    (tester) async {
      final chapter = [
        for (var i = 1; i <= 30; i++)
          Verse({
            'id': 'long-$i',
            'bookCode': 'GEN',
            'chapter': 1,
            'verse': i,
            'textZh': '经文 $i　${'用于验证连排、长按和定位的正文。' * 4}',
            'verseRef': 'GEN 1:$i',
            'sectionId': 'GEN.1',
          }),
      ];
      app.bible.verses = chapter;
      app.bible.byId = {for (final verse in chapter) verse.id: verse};
      app.bible.byChapter['GEN.1'] = chapter;
      app.notes = [
        {
          'id': 'long-note',
          'verseIds': ['long-5', 'long-16'],
        },
      ];
      await open(tester);
      router.go('/reference/1');
      await tester.pumpAndSettle();
      router.go('/reference/16');
      await tester.pumpAndSettle();
      final point = versePoint(tester, chapter[15]);
      expect(point.dy, greaterThan(80));
      expect(point.dy, lessThan(250));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      await tester.longPressAt(point);
      await tester.pumpAndSettle();
      expect(app.records, isEmpty);
      expect(toolbar, findsOneWidget);
      router.go('/reference/1');
      await tester.pumpAndSettle();
      expect(versePoint(tester, chapter.first).dy, lessThan(250));
      expect(toolbar, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multi-verse share uses one ordered request and cancellation retains selection',
    (tester) async {
      await open(tester, fullscreen: true);
      await tester.longPressAt(versePoint(tester, verses[1]));
      await tester.pumpAndSettle();
      await tester.tapAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      app.shareAccepted = false;
      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();
      expect(app.shares.single.map((verse) => verse.id), ['1', '2']);
      expect(toolbar, findsOneWidget);
      app.shareAccepted = true;
      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();
      expect(app.shares.length, 2);
      expect(app.shares.last.map((verse) => verse.id), ['1', '2']);
      expect(toolbar, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'my shares shows one card for multiple verses and excludes other records',
    (tester) async {
      app.records = [
        {
          'id': 'shared',
          'type': 'SCRIPTURE_SHARED',
          'verseId': '1',
          'verseIds': ['1', '3'],
          'content': verses
              .where((verse) => ['1', '3'].contains(verse.id))
              .map(app.bible.copyText)
              .join('\n'),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
        {
          'id': 'bookmark',
          'type': 'BOOKMARK_ADDED',
          'verseId': '2',
          'content': app.bible.copyText(verses[1]),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];
      await open(tester);
      router.go('/shares');
      await tester.pumpAndSettle();
      expect(find.text('选中'), findsNothing);
      expect(find.text('我的分享'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(SurfaceCard), findsOneWidget);
      expect(find.text('创世记 1:1,3 · 共 2 节'), findsOneWidget);
      expect(find.text(app.bible.copyText(verses[1])), findsNothing);
      await tester.tap(find.byType(SurfaceCard));
      await tester.pumpAndSettle();
      expect(find.text('目录选择 GEN 1:1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'marked verses retain solid tracks and note counts while selection and color rings toggle',
    (tester) async {
      app.bookmarks = [
        {'verseId': '1', 'color': highlightColors.first},
        {'verseId': '2', 'color': null},
      ];
      app.notes = [
        {
          'id': 'n1',
          'verseIds': ['1', '3'],
        },
        {
          'id': 'n2',
          'verseIds': ['1'],
        },
      ];
      await open(tester, size: const Size(360, 800), fullscreen: true);
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.foregroundPainter)
          .whereType<ScriptureMarksPainter>();
      final marks = painters.first.marks;
      expect(marks.map((mark) => mark.verseId), ['1', '2', '3']);
      expect(marks.map((mark) => mark.noteCount), [2, 0, 1]);
      await tester.longPressAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      final button = tester.widget<HighlightColorButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is HighlightColorButton &&
              widget.color == highlightColors.first,
        ),
      );
      expect(button.selected, isTrue);
      final ring =
          tester
                  .widgetList<Container>(
                    find.descendant(
                      of: find.byType(HighlightColorButton).first,
                      matching: find.byType(Container),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;
      expect((ring.border as Border).top.color, readingAccent);
      expect(
        verseStyle(tester, verses.first).decorationStyle,
        TextDecorationStyle.dashed,
      );
      if (const bool.fromEnvironment('LOGOS_CAPTURE_READER')) {
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            '../../../analysis/screenshots/logos-reader-marks-fixture.png',
          ),
        );
      }
      await tester.tap(find.bySemanticsLabel('高亮颜色 ${highlightColors.first}'));
      await tester.pumpAndSettle();
      expect(app.bookmarkFor('1'), isNotNull);
      expect(app.bookmarkFor('1')!['color'], isNull);
      expect(app.noteCountFor('1'), 2);
      await tester.longPressAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<HighlightColorButton>(find.byType(HighlightColorButton))
            .where((button) => button.selected),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'normal reading rejects long press; highlight-only verses have no solid track and use cancel highlight',
    (tester) async {
      app.bookmarks = [
        {'verseId': '1', 'color': highlightColors.first},
        {'verseId': '2', 'color': null},
        {'verseId': '3', 'color': highlightColors.first},
      ];
      app.notes = [
        {
          'id': 'n3',
          'verseIds': ['3'],
        },
      ];
      await open(tester);
      await tester.longPressAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      final marks = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.foregroundPainter)
          .whereType<ScriptureMarksPainter>()
          .first
          .marks;
      expect(marks.map((mark) => mark.verseId), ['2', '3']);
      await tester.tapAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      await tester.longPressAt(versePoint(tester, verses.first));
      await tester.pumpAndSettle();
      expect(find.text('取消高亮'), findsOneWidget);
      expect(find.text('取消收藏'), findsNothing);
      if (const bool.fromEnvironment('LOGOS_CAPTURE_READER')) {
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            '../../../analysis/screenshots/logos-reader-mark-rules-fixture.png',
          ),
        );
      }
      await tester.tap(find.text('取消高亮'));
      await tester.pumpAndSettle();
      expect(app.bookmarkFor('1'), isNull);
      expect(toolbar, findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fullscreen note badge opens all matching notes and supports editing',
    (tester) async {
      app.notes = [
        {
          'id': 'n1',
          'title': '第一条',
          'content': '第一条完整笔记正文',
          'verseIds': ['1'],
        },
        {
          'id': 'n2',
          'title': '第二条',
          'content': '第二条完整笔记正文',
          'verseIds': ['1', '2'],
        },
        {
          'id': 'n3',
          'title': '其他经文',
          'content': '不属于第一节',
          'verseIds': ['3'],
        },
      ];
      await open(tester, fullscreen: true);
      Offset badge() => tester
          .stateList<ScriptureParagraphState>(find.byType(ScriptureParagraph))
          .map((state) => state.noteBadgePoint('1'))
          .whereType<Offset>()
          .first;
      await tester.tapAt(badge());
      await tester.pumpAndSettle();
      expect(find.text('创世记 1:1 · 2 条笔记'), findsOneWidget);
      expect(find.text('第一条完整笔记正文'), findsOneWidget);
      expect(find.text('第二条完整笔记正文'), findsOneWidget);
      expect(find.text('不属于第一节'), findsNothing);
      expect(toolbar, findsNothing);
      if (const bool.fromEnvironment('LOGOS_CAPTURE_READER')) {
        await expectLater(
          find.byType(Overlay).first,
          matchesGoldenFile(
            '../../../analysis/screenshots/logos-verse-notes-fixture.png',
          ),
        );
      }
      await tester.tap(find.byTooltip('关闭笔记'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      await tester.tapAt(badge());
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑笔记').first);
      await tester.pumpAndSettle();
      expect(find.text('编辑测试笔记 n1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'brief success includes both animations within 1.5 seconds and replaces pending messages',
    (tester) async {
      await open(tester);
      final context = tester.element(find.byType(ReaderPage));
      toast(context, '第一次完成', brief: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      toast(context, '第二次完成', brief: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('第一次完成'), findsNothing);
      expect(find.text('第二次完成'), findsOneWidget);
      for (var i = 0; i < 17; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('第二次完成'), findsOneWidget);
      for (var i = 0; i < 9; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('第二次完成'), findsNothing);
    },
  );

  testWidgets(
    'continuous text and drop cap survive narrow screens and large type',
    (tester) async {
      app.fontSize = 30;
      app.lineHeight = 2.2;
      app.notes = [
        {
          'id': 'large-note',
          'verseIds': ['1', '2', '3'],
        },
      ];
      app.bookmarks = [
        {'verseId': '1', 'color': null},
      ];
      await open(tester, size: const Size(320, 800));
      expect(find.byType(ScriptureParagraph), findsOneWidget);
      final spans = tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(ScriptureParagraph),
          matching: find.byType(RichText),
        ),
      );
      final plain = spans.map((text) => text.text.toPlainText()).join();
      for (final verse in verses.take(3)) {
        expect(plain, contains(verse.text));
      }
      expect(tester.takeException(), isNull);
    },
  );
}

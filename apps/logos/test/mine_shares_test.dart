import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/main.dart' as product;
import 'package:logos/state/app_controller.dart';
import 'package:logos/ui/design.dart';

class MineTestController extends AppController {
  MineTestController() : super(store: LocalStore(NativeDatabase.memory()));
  @override
  Future<void> boot() async {}
}

void main() {
  late MineTestController app;
  setUp(() {
    app = MineTestController()..ready = true;
    app.records = [
      for (final type in [
        'SCRIPTURE_SHARED',
        'SCRIPTURE_HIGHLIGHT',
        'BOOKMARK_ADDED',
        'NOTE_CREATED',
      ])
        {
          'id': type,
          'type': type,
          'content': '测试$type',
          'createdAt': '2026-10-17T08:00:00Z',
        },
    ];
    product.router.go('/mine');
  });
  tearDown(() async => app.store.close());

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
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

  for (final wide in [false, true]) {
    testWidgets('mine shares navigation works with wide=$wide', (tester) async {
      await open(tester, Size(wide ? 1100 : 400, 1000));
      expect(find.text('记录'), findsNothing);
      expect(find.byIcon(Icons.edit_note_outlined), findsOneWidget);
      if (wide) {
        expect(find.byType(NavigationBar), findsNothing);
      } else {
        expect(find.byType(NavigationDestination), findsNWidgets(3));
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2,
        );
      }
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      expect(product.router.routeInformationProvider.value.uri.path, '/plans');
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      expect(product.router.routeInformationProvider.value.uri.path, '/mine');
      await tester.ensureVisible(find.text('我的分享'));
      await tester.tap(find.text('我的分享'));
      await tester.pumpAndSettle();
      expect(find.text('我的分享'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byIcon(Icons.person_outline), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(SurfaceCard), findsOneWidget);
      expect(find.text('测试SCRIPTURE_SHARED'), findsOneWidget);
      expect(find.text('测试SCRIPTURE_HIGHLIGHT'), findsNothing);
      expect(find.text('测试BOOKMARK_ADDED'), findsNothing);
      expect(find.text('测试NOTE_CREATED'), findsNothing);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(product.router.routeInformationProvider.value.uri.path, '/mine');
      expect(app.records.length, 4);

      app.records.removeWhere((record) => record['type'] == 'SCRIPTURE_SHARED');
      await tester.tap(find.text('我的分享'));
      await tester.pumpAndSettle();
      expect(find.text('还没有分享记录'), findsOneWidget);
      expect(find.text('分享过的经文会保存在这里。'), findsOneWidget);
      expect(find.byType(SurfaceCard), findsNothing);
      expect(app.records.length, 3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('legacy records route opens my shares outside main navigation', (
    tester,
  ) async {
    await open(tester, const Size(400, 1000));
    product.router.go('/records');
    await tester.pumpAndSettle();
    expect(product.router.routeInformationProvider.value.uri.path, '/shares');
    expect(find.text('我的分享'), findsOneWidget);
    expect(find.text('测试SCRIPTURE_SHARED'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'state/app_controller.dart';
import 'data/bible_models.dart';
import 'ui/design.dart';
import 'ui/home_pages.dart';
import 'ui/reader.dart';
import 'ui/catalog_page.dart';
import 'ui/search_page.dart';
import 'ui/library_pages.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LogosApp()));
}

final router = GoRouter(
  initialLocation: '/home',
  redirect: (context, state) {
    if (state.uri.scheme == 'logos' && state.uri.host == 'verse') {
      final parts = state.uri.path.replaceFirst('/', '').split('.');
      if (parts.length == 3) {
        return '/read/${parts[0]}/${parts[1]}?verse=${parts[2]}';
      }
      return '/home';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/home'),
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(path: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomePage()),
        GoRoute(path: '/plans', builder: (_, _) => const PlansPage()),
        GoRoute(path: '/mine', builder: (_, _) => const MinePage()),
      ],
    ),
    GoRoute(path: '/shares', builder: (_, _) => const SharesPage()),
    GoRoute(path: '/records', redirect: (_, _) => '/shares'),
    GoRoute(
      path: '/catalog',
      builder: (_, state) => CatalogPage(
        pickOnly: state.uri.queryParameters['pick'] == 'true',
        initialPosition: state.uri.queryParameters['book'] == null
            ? null
            : ChapterPosition(
                state.uri.queryParameters['book']!,
                int.tryParse(state.uri.queryParameters['chapter'] ?? '') ?? 1,
              ),
      ),
    ),
    GoRoute(
      path: '/read/:book/:chapter',
      builder: (_, state) => ReaderPage(
        bookCode: state.pathParameters['book']!,
        chapter: int.tryParse(state.pathParameters['chapter']!) ?? 1,
        verse: int.tryParse(state.uri.queryParameters['verse'] ?? '') ?? 1,
      ),
    ),
    GoRoute(
      path: '/search',
      builder: (_, state) =>
          SearchPage(initial: state.uri.queryParameters['q'] ?? ''),
    ),
    GoRoute(path: '/notes', builder: (_, _) => const NotesPage()),
    GoRoute(
      path: '/note/new',
      builder: (_, state) => NoteEditor(
        verseIds: (state.uri.queryParameters['verses'] ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
      ),
    ),
    GoRoute(
      path: '/note/:id',
      builder: (_, state) => NoteEditor(id: state.pathParameters['id']),
    ),
    GoRoute(path: '/bookmarks', builder: (_, _) => const BookmarksPage()),
    GoRoute(path: '/history', builder: (_, _) => const HistoryPage()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    GoRoute(path: '/about', builder: (_, _) => const AboutPage()),
    GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
    GoRoute(
      path: '/verse/:reference',
      redirect: (_, state) {
        final parts = state.pathParameters['reference']!.split('.');
        return parts.length == 3
            ? '/read/${parts[0]}/${parts[1]}?verse=${parts[2]}'
            : '/home';
      },
    ),
  ],
  errorBuilder: (_, _) => const Scaffold(
    body: EmptyState(
      icon: Icons.link_off,
      title: '找不到这个页面',
      message: '请从首页重新进入。',
    ),
  ),
);

class LogosApp extends ConsumerWidget {
  const LogosApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return MaterialApp.router(
      title: 'Logos · 话语之间',
      debugShowCheckedModeBanner: false,
      theme: logosTheme(false),
      darkTheme: logosTheme(true),
      themeMode: app.dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      builder: (context, child) {
        if (!app.ready) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (app.error != null && !app.accounts.guestLocked) {
          return Scaffold(
            body: EmptyState(
              icon: Icons.error_outline,
              title: '暂时无法打开',
              message: app.error!,
            ),
          );
        }
        if (app.accounts.guestLocked && !app.accounts.transitioning) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(app.accounts.syncError ?? '个人数据转移尚未完成，数据已保留在原账号下。'),
                  TextButton(
                    onPressed: () async {
                      try {
                        await app.recoverAccountTransfer();
                      } catch (_) {
                        /* Keep the source quarantined until recovery succeeds. */
                      }
                    },
                    child: const Text('重试恢复'),
                  ),
                ],
              ),
            ),
          );
        }
        return Stack(
          children: [
            child!,
            if (app.accounts.transitioning)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在切换账号与整理本地数据…'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

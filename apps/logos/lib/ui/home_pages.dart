import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../state/app_controller.dart';
import 'design.dart';

const tabs = ['/home', '/plans', '/mine'];
const tabLabels = ['首页', '阅读计划', '我的'];
const tabIcons = [
  Icons.auto_stories_outlined,
  Icons.calendar_month_outlined,
  Icons.person_outline,
];

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final selected = tabs.indexOf(path).clamp(0, tabs.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 820;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 112,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    right: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 30),
                    const Text(
                      'λ',
                      style: TextStyle(
                        fontSize: 46,
                        fontFamily: 'serif',
                        color: forest,
                      ),
                    ),
                    const Text(
                      'LOGOS',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 3,
                        color: forest,
                      ),
                    ),
                    const SizedBox(height: 45),
                    for (var i = 0; i < tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          children: [
                            IconButton.filledTonal(
                              isSelected: selected == i,
                              onPressed: () => context.go(tabs[i]),
                              icon: Icon(tabIcons[i]),
                              style: IconButton.styleFrom(
                                backgroundColor: selected == i
                                    ? forest.withValues(alpha: .12)
                                    : Colors.transparent,
                              ),
                            ),
                            Text(
                              tabLabels[i],
                              style: TextStyle(
                                fontSize: 12,
                                color: selected == i
                                    ? forest
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: '设置',
                      onPressed: () => context.push('/settings'),
                      icon: const Icon(Icons.tune, size: 21),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (i) => context.go(tabs[i]),
              destinations: [
                for (var i = 0; i < tabs.length; i++)
                  NavigationDestination(
                    icon: Icon(tabIcons[i]),
                    label: tabLabels[i],
                  ),
              ],
            ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final verse = app.bible.dailyVerse;
    final b = app.bible.book(app.last.bookCode);
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final wide = MediaQuery.sizeOf(context).width > 950;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        wide ? 48 : 22,
        wide ? 36 : 22,
        wide ? 48 : 22,
        30,
      ),
      children: [
        Row(
          children: [
            if (!wide) ...[
              const Text(
                'λ',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 34,
                  color: forest,
                ),
              ),
              const SizedBox(width: 9),
            ],
            const Text(
              'LOGOS',
              style: TextStyle(
                fontSize: 15,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
                color: forest,
              ),
            ),
            const Spacer(),
            Text(
              '${now.month.toString().padLeft(2, '0')} / ${now.day.toString().padLeft(2, '0')}  ${['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][now.weekday - 1]}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),
        Text('让话语，照亮今天。', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 10),
        Text(
          '放慢脚步，在每一次阅读中与真理相遇。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 28),
        SurfaceCard(
          onTap: () => context.push('/search'),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.search, color: forest, size: 22),
              const SizedBox(width: 12),
              Text(
                '搜索经文或引用，如「约 3:16」',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward, size: 17, color: forest),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (!app.bible.unlocked) ...[
          SurfaceCard(
            color: forest.withValues(alpha: .06),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('先把话语带到身边', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(
                  app.connecting
                      ? '正在连接经文服务，首次解锁需要联网…'
                      : '首次阅读需连接 Logos 服务获取密钥。目录已可离线浏览。',
                ),
                if (app.connectionError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      app.connectionError!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: app.connecting ? null : app.reconnect,
                      child: const Text('连接服务'),
                    ),
                    TextButton(
                      onPressed: () => context.push('/settings'),
                      child: const Text('服务设置'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        SurfaceCard(
          color: app.dark ? const Color(0xff27352b) : const Color(0xffe9eee5),
          padding: EdgeInsets.all(wide ? 32 : 24),
          onTap: verse == null
              ? null
              : () => context.push(
                  '/read/${verse.bookCode}/${verse.chapter}?verse=${verse.number}',
                ),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                bottom: -45,
                child: IgnorePointer(
                  child: CustomPaint(
                    size: const Size(230, 210),
                    painter: LandscapePainter(),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.wb_sunny_outlined,
                        size: 16,
                        color: forest,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '每日经文',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 2,
                          color: forest,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${now.year}.${now.month}.${now.day}',
                        style: const TextStyle(color: forest, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: Text(
                      verse?.text ?? '你的话是我脚前的灯，\n是我路上的光。',
                      style: TextStyle(
                        fontSize: wide ? 26 : 22,
                        height: 1.9,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    verse == null
                        ? '诗篇 119:105'
                        : '${app.bible.book(verse.bookCode).name} ${verse.chapter}:${verse.label}',
                    style: const TextStyle(
                      color: forest,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Row(
                    children: [
                      Expanded(
                        child: Text(
                          '慢慢读，留意今天触动你的一个词。',
                          style: TextStyle(fontSize: 12, color: forest),
                        ),
                      ),
                      Icon(Icons.arrow_outward, size: 20, color: forest),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Text('回到话语中', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/catalog'),
              child: const Text('圣经目录 →'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SurfaceCard(
          onTap: () => context.push(app.last.route),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 64,
                decoration: BoxDecoration(
                  color: forest,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Center(
                  child: Icon(
                    Icons.menu_book_outlined,
                    color: Color(0xffe9e6ce),
                    size: 25,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '继续阅读',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${b.name}  第 ${app.last.chapter} 章',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '新标点和合本 · CUVs',
                      style: TextStyle(fontSize: 11, color: gold),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: forest, size: 22),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _QuickLink(
                icon: Icons.grid_view_outlined,
                title: '圣经目录',
                subtitle: '66 卷 · 1,189 章',
                onTap: () => context.push('/catalog'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _QuickLink(
                icon: Icons.bookmark_border,
                title: '我的收藏',
                subtitle: '${app.bookmarks.length} 处话语的印记',
                onTap: () => context.push('/bookmarks'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Center(
          child: Text(
            '起初有道，道与神同在，道就是神。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: forest, size: 24),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class LandscapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = forest.withValues(alpha: .055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 10; i++) {
      final path = Path()
        ..moveTo(0, size.height * .5 + i * 9)
        ..cubicTo(
          size.width * .45,
          -20 + i * 14,
          size.width * .6,
          size.height + i * 8,
          size.width * 1.2,
          20 + i * 12,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PlansPage extends StatelessWidget {
  const PlansPage({super.key});
  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.calendar_month_outlined,
    title: '为阅读，留一段时光',
    message: '个人阅读计划将在 Phase 1.5 开启。\n现在可以从首页继续阅读，已读章节会自动记录。',
  );
}

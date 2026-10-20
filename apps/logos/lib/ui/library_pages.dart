import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/bible_models.dart';
import '../data/local_store.dart';
import '../state/app_controller.dart';
import 'design.dart';
import 'reader.dart';
import 'catalog_page.dart';

class SharesPage extends ConsumerStatefulWidget {
  const SharesPage({super.key});
  @override
  ConsumerState<SharesPage> createState() => _SharesState();
}

class _SharesState extends ConsumerState<SharesPage> {
  int limit = 30;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final records = app.records
        .where((record) => record['type'] == 'SCRIPTURE_SHARED')
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的分享'),
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => backOrHome(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: records.isEmpty
          ? const EmptyState(
              icon: Icons.ios_share_outlined,
              title: '还没有分享记录',
              message: '分享过的经文会保存在这里。',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
              itemCount:
                  records.take(limit).length + (records.length > limit ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                if (index == limit) {
                  return TextButton(
                    onPressed: () => setState(() => limit += 30),
                    child: const Text('加载更多分享'),
                  );
                }
                final record = records[index];
                final sharedIds =
                    (record['verseIds'] as List?) ?? [record['verseId']];
                final sharedVerses = sharedIds
                    .map((id) => app.bible.byId[id])
                    .whereType<Verse>()
                    .toList();
                final verse =
                    app.bible.byId[record['verseId']] ??
                    sharedVerses.firstOrNull;
                final reference = sharedVerses.isNotEmpty
                    ? app.bible.formatReferences(sharedVerses)
                    : verse == null
                    ? ''
                    : app.bible.formatReferences([verse]);
                return SurfaceCard(
                  onTap: verse == null
                      ? null
                      : () => context.push(
                          ChapterPosition(
                            verse.bookCode,
                            verse.chapter,
                            verse: verse.number,
                          ).route,
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.ios_share_outlined,
                            size: 17,
                            color: gold,
                          ),
                          const SizedBox(width: 9),
                          const Text(
                            '分享',
                            style: TextStyle(fontSize: 12, color: gold),
                          ),
                          const Spacer(),
                          Text(
                            friendlyDate(record['createdAt'] as String),
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        record['content'] as String? ?? '',
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, height: 1.85),
                      ),
                      if (reference.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          '$reference · 共 ${sharedIds.length} 节',
                          style: const TextStyle(fontSize: 11, color: forest),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class MinePage extends ConsumerWidget {
  const MinePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 14),
        Text('我的', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 26),
        SurfaceCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: forest,
                child: Text(
                  'λ',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 40,
                    color: Color(0xffe6e5d1),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.accounts.account?.nickname ?? '平安，读者',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      app.accounts.account == null
                          ? '游客模式 · 数据保存在此设备'
                          : app.accounts.syncing
                          ? '开发账号 · 同步中'
                          : '开发账号 · 待上传 ${app.accounts.pendingCount} 项',
                      style: const TextStyle(fontSize: 11, color: gold),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '登录信息',
                onPressed: () => context.push('/login'),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('${app.progress.length}', '读过章节'),
              _stat('${app.bookmarks.length}', '收藏与高亮'),
              _stat('${app.notes.length}', '读经笔记'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _menu(context, Icons.edit_note_outlined, '我的笔记', '/notes'),
              _menu(context, Icons.ios_share_outlined, '我的分享', '/shares'),
              _menu(context, Icons.bookmark_border, '收藏与高亮', '/bookmarks'),
              _menu(context, Icons.history, '阅读历史与进度', '/history'),
              _menu(context, Icons.tune, '设置', '/settings'),
              _menu(context, Icons.info_outline, '关于 Logos', '/about'),
            ],
          ),
        ),
        const SizedBox(height: 30),
        const Center(
          child: Text(
            'LOGOS  ·  话语之间',
            style: TextStyle(letterSpacing: 2, fontSize: 11, color: gold),
          ),
        ),
      ],
    );
  }

  Widget _stat(String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 25,
          color: forest,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: gold)),
    ],
  );
  Widget _menu(
    BuildContext context,
    IconData icon,
    String title,
    String route,
  ) => ListTile(
    leading: Icon(icon, color: forest, size: 23),
    title: Text(title, style: const TextStyle(fontSize: 14)),
    trailing: const Icon(Icons.chevron_right, size: 18),
    onTap: () => context.push(route),
  );
}

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});
  @override
  ConsumerState<NotesPage> createState() => _NotesState();
}

class _NotesState extends ConsumerState<NotesPage> {
  String query = '';
  String? tag;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final notes = app.notes
        .where(
          (n) =>
              ('${n['title']} ${n['content']}').toLowerCase().contains(
                query.toLowerCase(),
              ) &&
              (tag == null || (n['tags'] as List).contains(tag)),
        )
        .toList();
    final tags =
        app.notes
            .expand((n) => (n['tags'] as List).cast<String>())
            .toSet()
            .toList()
          ..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('我的笔记')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/note/new'),
        tooltip: '新建笔记',
        child: const Icon(Icons.add),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: const InputDecoration(
                    hintText: '搜索标题与正文',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              if (tags.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('全部'),
                        selected: tag == null,
                        onSelected: (_) => setState(() => tag = null),
                      ),
                      for (final t in tags)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(t),
                            selected: tag == t,
                            onSelected: (_) => setState(() => tag = t),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: notes.isEmpty
                    ? EmptyState(
                        icon: Icons.edit_note,
                        title: query.isEmpty ? '写下此刻的领受' : '没有匹配的笔记',
                        message: '笔记可以关联多节经文，并用标签整理。',
                        action: TextButton(
                          onPressed: () => context.push('/note/new'),
                          child: const Text('写第一篇笔记'),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                        itemCount: notes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final n = notes[index];
                          return SurfaceCard(
                            onTap: () => context.push('/note/${n['id']}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (n['title'] as String).isEmpty
                                      ? '无标题笔记'
                                      : n['title'] as String,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  n['content'] as String,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '${friendlyDate(n['updatedAt'] as String)}  ·  ${(n['verseIds'] as List).length} 节经文',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: gold,
                                  ),
                                ),
                                if ((n['tags'] as List).isNotEmpty)
                                  Text(
                                    (n['tags'] as List)
                                        .map((t) => '#$t')
                                        .join('  '),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: forest,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({super.key, this.id, this.verseIds = const []});
  final String? id;
  final List<String> verseIds;
  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  final title = TextEditingController();
  final content = TextEditingController();
  final tags = TextEditingController();
  List<String> verseIds = [];
  bool busy = false;
  bool initialized = false;
  LocalStore? _draftStore;

  void removeReference(Verse verse) => setState(
    () => verseIds.removeWhere((id) {
      final item = ref.read(appProvider).bible.byId[id];
      return item != null &&
          item.bookCode == verse.bookCode &&
          item.chapter == verse.chapter &&
          item.bridgeStart == verse.bridgeStart;
    }),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      _draftStore = ref.read(appProvider).store;
      final note = ref
          .read(appProvider)
          .notes
          .where((n) => n['id'] == widget.id)
          .firstOrNull;
      title.text = note?['title'] as String? ?? '';
      content.text = note?['content'] as String? ?? '';
      tags.text = (note?['tags'] as List? ?? []).join('，');
      verseIds = (note?['verseIds'] as List? ?? widget.verseIds)
          .cast<String>()
          .toList();
      initialized = true;
    }
  }

  @override
  void dispose() {
    title.dispose();
    content.dispose();
    tags.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!identical(_draftStore, ref.read(appProvider).store)) {
      toast(context, '账号已变化，请返回当前账号重新打开笔记');
      return;
    }
    if (content.text.trim().isEmpty) {
      toast(context, '请先写下笔记正文');
      return;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(appProvider)
          .saveNote(
            id: widget.id,
            title: title.text.trim(),
            content: content.text,
            verseIds: verseIds,
            tags: tags.text
                .split(RegExp('[,，]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList(),
          );
      if (mounted) {
        toast(context, '笔记已保存到此设备', brief: true);
        backOrHome(context);
      }
    } catch (error) {
      if (mounted) {
        toast(context, '保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> addReference() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final bible = ref.read(appProvider).bible;
    final first = verseIds
        .map((id) => bible.byId[id])
        .whereType<Verse>()
        .firstOrNull;
    final value = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => CatalogPage(
          selectVerses: true,
          initialVerseIds: List.of(verseIds),
          initialPosition: first == null
              ? bible.books.isEmpty
                    ? null
                    : ChapterPosition(bible.books.first.code, 1)
              : ChapterPosition(first.bookCode, first.chapter),
        ),
      ),
    );
    if (value != null && mounted) setState(() => verseIds = value);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final references = <Verse>[];
    final seen = <String>{};
    for (final id in verseIds) {
      final verse = app.bible.byId[id];
      if (verse != null &&
          seen.add('${verse.bookCode}.${verse.chapter}.${verse.bridgeStart}')) {
        references.add(verse);
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? '写笔记' : '编辑笔记'),
        actions: [
          if (widget.id != null)
            IconButton(
              tooltip: '删除笔记',
              onPressed: () async {
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('删除这篇笔记？'),
                    content: const Text('删除后无法恢复，阅读记录会保留摘要。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('保留'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (sure == true) {
                  await app.removeNote(widget.id!);
                  if (context.mounted) {
                    backOrHome(context);
                  }
                }
              },
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            onPressed: busy ? null : save,
            child: Text(busy ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              TextField(
                controller: title,
                maxLength: 200,
                style: Theme.of(context).textTheme.headlineMedium,
                decoration: const InputDecoration(
                  hintText: '为这次领受起个名字',
                  counterText: '',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text(
                    '关联经文',
                    style: TextStyle(fontSize: 12, color: gold),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: busy ? null : addReference,
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('添加'),
                  ),
                ],
              ),
              for (final verse in references)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(15),
                    color: forest.withValues(alpha: .05),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.bible.copyText(verse),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        IconButton(
                          tooltip: '移除经文关联',
                          onPressed: () => removeReference(verse),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: content,
                minLines: 12,
                maxLines: null,
                maxLength: 50000,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 17, height: 1.9),
                decoration: const InputDecoration(
                  hintText: '这段经文让我看见了什么？\n我想如何回应？',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                ),
              ),
              const Divider(height: 30),
              TextField(
                controller: tags,
                decoration: const InputDecoration(
                  labelText: '标签',
                  hintText: '用逗号分隔，如：灵修，祷告',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '自动关联个人记录流 · 纯文本笔记 · 保存在当前设备',
                style: TextStyle(fontSize: 10, color: gold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookmarksPage extends ConsumerWidget {
  const BookmarksPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('收藏与高亮')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: app.bookmarks.isEmpty
              ? const EmptyState(
                  icon: Icons.bookmark_border,
                  title: '珍藏触动你的话语',
                  message: '在读经页轻点一节经文，即可收藏或选择高亮颜色。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(22),
                  itemCount: app.bookmarks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final bookmark = app.bookmarks[index];
                    final verse = app.bible.byId[bookmark['verseId']];
                    if (verse == null) {
                      return const ListTile(title: Text('连接服务或解锁离线经文后查看收藏正文'));
                    }
                    return SurfaceCard(
                      onTap: () => context.push(
                        ChapterPosition(
                          verse.bookCode,
                          verse.chapter,
                          verse: verse.number,
                        ).route,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (bookmark['color'] != null) ...[
                                CircleAvatar(
                                  radius: 6,
                                  backgroundColor: Color(
                                    int.parse(
                                      (bookmark['color'] as String)
                                          .replaceFirst('#', 'ff'),
                                      radix: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 9),
                              ],
                              Text(
                                '${app.bible.book(verse.bookCode).name} ${verse.chapter}:${verse.label}',
                                style: const TextStyle(
                                  color: forest,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: '编辑收藏',
                                onPressed: () =>
                                    verseActions(context, app, verse),
                                icon: const Icon(Icons.more_horiz, size: 20),
                              ),
                            ],
                          ),
                          Text(
                            verse.text,
                            style: const TextStyle(fontSize: 17, height: 1.9),
                          ),
                          if ((bookmark['note'] as String? ?? '').isNotEmpty)
                            Text(
                              bookmark['note'] as String,
                              style: const TextStyle(color: gold, fontSize: 12),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('阅读历史与进度')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: app.progress.isEmpty
              ? const EmptyState(
                  icon: Icons.history,
                  title: '从第一章开始',
                  message: '阅读章节后，最近的位置会保存在这里。',
                )
              : ListView(
                  padding: const EdgeInsets.all(22),
                  children: [
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '已访问 ${app.progress.length} / 1189 章',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 15),
                          LinearProgressIndicator(
                            value: app.progress.length / 1189,
                            color: forest,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '表示打开过的章节，不代表已经读完。',
                            style: TextStyle(fontSize: 11, color: gold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final p in app.progress)
                      ListTile(
                        leading: const Icon(
                          Icons.menu_book_outlined,
                          color: forest,
                        ),
                        title: Text(
                          '${app.bible.book(p['bookCode'] as String).name} ${p['chapter']}',
                        ),
                        subtitle: Text(
                          '第 ${p['verse']} 节 · ${friendlyDate(p['updatedAt'] as String)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => context.push(
                          ChapterPosition(
                            p['bookCode'] as String,
                            p['chapter'] as int,
                            verse: p['verse'] as int,
                          ).route,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<SettingsPage> {
  bool downloading = false;
  bool endpointOpen = false;
  final server = TextEditingController();
  @override
  void dispose() {
    server.dispose();
    super.dispose();
  }

  Future<void> download() async {
    setState(() => downloading = true);
    try {
      await ref.read(appProvider).bible.download();
      if (mounted) {
        toast(context, '离线经文已下载，可以断网阅读与搜索');
      }
    } catch (error) {
      if (mounted) {
        toast(
          context,
          '下载失败：${error.toString().replaceFirst('Bad state: ', '')}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Text('让阅读更自在', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('夜间模式'),
                      subtitle: const Text('设置会保存在此设备'),
                      value: app.dark,
                      onChanged: app.theme,
                    ),
                    ListTile(
                      leading: const Icon(Icons.text_fields),
                      title: const Text('字号与行距'),
                      subtitle: Text(
                        '${app.fontSize.toInt()} 号 · ${app.lineHeight.toStringAsFixed(1)} 倍行距',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => readingSettings(context, app),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('离线圣经', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          app.bible.offlineReady
                              ? Icons.offline_pin_outlined
                              : Icons.cloud_download_outlined,
                          color: forest,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          app.bible.offlineReady ? '已准备好离线阅读' : '把话语随身携带',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '首次下载需要联网。下载后可在断网时阅读、搜索、收藏和写笔记。清除经文缓存不会删除个人记录。',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: downloading ? null : download,
                          icon: const Icon(Icons.download, size: 18),
                          label: Text(
                            downloading
                                ? '正在下载与加密…'
                                : app.bible.offlineReady
                                ? '重新下载'
                                : '下载离线经文',
                          ),
                        ),
                        if (app.bible.offlineReady)
                          TextButton(
                            onPressed: downloading
                                ? null
                                : () async {
                                    await app.bible.clearCache();
                                    if (mounted) {
                                      setState(() {});
                                      if (context.mounted) {
                                        toast(context, '已清除经文缓存，个人记录保留');
                                      }
                                    }
                                  },
                            child: const Text('清除经文缓存'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.privacy_tip_outlined,
                        color: forest,
                      ),
                      title: const Text('个人数据备份'),
                      subtitle: Text(
                        app.accounts.account == null
                            ? '游客笔记与收藏只保存在当前设备'
                            : '导出当前账号在此设备上的个人数据',
                      ),
                      trailing: const Icon(Icons.file_upload_outlined),
                      onTap: () async {
                        final payload = jsonEncode({
                          'format': 'logos-personal-export-v1',
                          if (app.accounts.account != null)
                            'account': {
                              'userId': app.accounts.account!.userId,
                              'server': app.accounts.account!.server,
                            },
                          'exportedAt': DateTime.now()
                              .toUtc()
                              .toIso8601String(),
                          'bookmarks': app.bookmarks,
                          'notes': app.notes,
                          'progress': app.progress,
                          'feed': app.records,
                        });
                        await Clipboard.setData(ClipboardData(text: payload));
                        if (context.mounted) {
                          toast(context, '个人数据 JSON 已复制，请保存在你自己的安全位置');
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.dns_outlined, color: forest),
                      title: const Text('经文服务连接'),
                      subtitle: Text(
                        app.bible.server,
                        style: const TextStyle(fontSize: 10),
                      ),
                      trailing: Icon(
                        endpointOpen ? Icons.expand_less : Icons.expand_more,
                      ),
                      onTap: () {
                        server.text = app.bible.server;
                        setState(() => endpointOpen = !endpointOpen);
                      },
                    ),
                    if (endpointOpen)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            TextField(
                              controller: server,
                              decoration: const InputDecoration(
                                labelText: 'GraphQL 服务地址',
                                hintText: 'https://你的服务/graphql',
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: app.connecting
                                  ? null
                                  : () async {
                                      try {
                                        await app.setServer(server.text.trim());
                                        if (context.mounted) {
                                          toast(
                                            context,
                                            app.connectionError ?? '已连接经文服务',
                                          );
                                        }
                                      } catch (error) {
                                        if (context.mounted) {
                                          toast(context, error.toString());
                                        }
                                      }
                                    },
                              child: Text(app.connecting ? '连接中…' : '保存并连接'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Logos 0.1.0 · 第一阶段开发版',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: gold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于 Logos')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const Center(
              child: Text(
                'λόγος',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 60,
                  color: forest,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text('让话语，照亮今天。', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 35),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '经文来源与版权',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '圣经文本采用《新标点和合本》（CUVs），文本来源 eBible.org（ebible.org），属公共领域。\n\n本应用独立开发。微读圣经仅作为基础交互研究参考，Logos 与微读圣经无隶属关系。未使用其商标、代码、图标、字体或内容资源。\n\n如对文本内容有疑问，请以纸质圣经为准。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '隐私与使用范围',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '游客收藏、笔记、阅读历史与分享保存在当前设备。选择连接开发账号并同意合并后，这些数据会归入该账号，并上传到配置的 Logos 服务。登录期间的修改会继续同步；断网或退出时，未上传数据保留在原账号的本地库中，重新连接后续传。\n\n退出后使用全新的游客业务数据，不显示其他账号的缓存。设备经文离线包与显示设置保留。卸载应用会删除本地缓存和未上传数据，可在设置中导出当前个人数据。\n\n此版本为私有开发与内测用途，不包含统计 SDK、广告、社交功能或 AI 问答。正式短信、令牌刷新与服务端会话撤销仍待接入；退出当前设备会移除本机登录凭证。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            const Center(
              child: Text(
                '0.1.0 · 构建 2 · 以话语为根基',
                style: TextStyle(fontSize: 11, color: gold),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginState();
}

class _LoginState extends ConsumerState<LoginPage> {
  final phone = TextEditingController();
  final code = TextEditingController();
  final invite = TextEditingController();
  bool consent = false;
  bool busy = false;
  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    invite.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!consent) {
      toast(context, '请先阅读并同意当前数据处理说明');
      return;
    }
    setState(() => busy = true);
    final app = ref.read(appProvider);
    try {
      await app.login(
        phone: phone.text.trim(),
        code: code.text.trim(),
        invite: invite.text.trim(),
      );
      if (mounted) {
        toast(context, '开发账号已连接，数据已归入此账号，将继续同步。');
        context.go('/mine');
      }
    } catch (error) {
      if (mounted) {
        toast(context, error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    final app = ref.read(appProvider);
    final pending = app.accounts.pendingCount;
    setState(() => busy = true);
    try {
      await app.logout();
      if (mounted) {
        toast(
          context,
          pending > 0 ? '已退出。未上传数据保留在原账号，重新连接后续传。' : '已退出，返回游客模式。',
        );
        context.go('/mine');
      }
    } catch (error) {
      if (mounted) {
        toast(context, error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final accounts = app.accounts;
    final account = accounts.account;
    final disabled = busy || accounts.transitioning;
    return Scaffold(
      appBar: AppBar(title: const Text('账号与同步')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(26),
            children: [
              const Text(
                '与话语，继续同行',
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 14),
              if (account != null) ...[
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${account.nickname} · ${account.phone}'),
                      const SizedBox(height: 12),
                      Text(
                        accounts.syncing
                            ? '正在同步 · 已处理 ${accounts.uploadedCount} 项'
                            : '待上传 ${accounts.pendingCount} 项',
                        key: const ValueKey('sync-status'),
                      ),
                      if (accounts.syncing) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ],
                      if (accounts.lastSyncedAt != null)
                        Text(
                          '上次同步 ${friendlyDate(accounts.lastSyncedAt!.toIso8601String())}',
                          style: const TextStyle(fontSize: 12, color: gold),
                        ),
                      if (accounts.syncError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            accounts.syncError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: disabled || accounts.syncing
                            ? null
                            : accounts.sync,
                        child: const Text('立即同步'),
                      ),
                      OutlinedButton(
                        onPressed: disabled ? null : logout,
                        child: const Text('退出当前账号'),
                      ),
                      const Text(
                        '未上传数据会保留在此账号，退出后重新连接可续传。',
                        style: TextStyle(fontSize: 12, color: gold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text('重新连接当前账号', style: TextStyle(fontSize: 17)),
              ] else
                const Text(
                  '当前使用开发验证码。连接后，本机游客的收藏、笔记、阅读进度和分享会合并到所选账号，并继续同步到配置的 Logos 服务。正式短信通道尚未配置。',
                  style: TextStyle(fontSize: 13, color: gold),
                ),
              const SizedBox(height: 24),
              TextField(
                controller: phone,
                enabled: !disabled,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                decoration: const InputDecoration(labelText: '开发测试手机号'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: code,
                enabled: !disabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '开发验证码'),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: invite,
                enabled: !disabled,
                decoration: const InputDecoration(labelText: '开发邀请码'),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: consent,
                onChanged: disabled
                    ? null
                    : (value) => setState(() => consent = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  account == null
                      ? '我同意将手机号发送到配置的 Logos 服务，并将本机游客的个人数据合并、同步到此账号。'
                      : '我了解重新连接会发送手机号，并继续同步此账号的个人数据。',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: disabled ? null : login,
                child: Text(
                  busy
                      ? '处理中…'
                      : account == null
                      ? '连接开发账号并合并'
                      : '重新连接当前账号',
                ),
              ),
              if (account == null)
                TextButton(
                  onPressed: disabled ? null : () => backOrHome(context),
                  child: const Text('继续以游客身份阅读'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

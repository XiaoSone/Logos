import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'reading_style.dart';
import 'scripture_text.dart';
import '../data/bible_models.dart';
import '../state/app_controller.dart';
import 'design.dart';

void backOrHome(BuildContext context) =>
    context.canPop() ? context.pop() : context.go('/home');

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({
    super.key,
    required this.bookCode,
    required this.chapter,
    this.verse = 1,
  });
  final String bookCode;
  final int chapter;
  final int verse;
  @override
  ConsumerState<ReaderPage> createState() => _ReaderState();
}

class _ReaderState extends ConsumerState<ReaderPage> {
  PageController? pages;
  int current = 0;
  final selected = <String>{};
  bool fullscreen = false;
  bool savingSelection = false;
  bool get selecting => selected.isNotEmpty;

  void setFullscreen(bool value) {
    setState(() => fullscreen = value);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  void clearSelection() => setState(selected.clear);

  void readingTap() {
    if (savingSelection) return;
    if (selecting) {
      clearSelection();
    } else {
      setFullscreen(!fullscreen);
    }
  }

  void toggleVerse(Verse verse) {
    if (savingSelection) return;
    if (!selecting) {
      readingTap();
      return;
    }
    setState(() {
      if (!selected.remove(verse.id)) selected.add(verse.id);
    });
  }

  void selectVerse(Verse verse) {
    if (!fullscreen || savingSelection || selected.contains(verse.id)) return;
    setState(() => selected.add(verse.id));
  }

  List<Verse> get selectedVerses => ref
      .read(appProvider)
      .bible
      .verses
      .where((verse) => selected.contains(verse.id))
      .toList();

  void openSelectionNote() {
    final ids = selectedVerses.map((verse) => verse.id).join(',');
    clearSelection();
    if (fullscreen) setFullscreen(false);
    context.push(
      Uri(path: '/note/new', queryParameters: {'verses': ids}).toString(),
    );
  }

  Future<void> saveSelection({
    String? color,
    bool clearHighlightOnly = false,
  }) async {
    final app = ref.read(appProvider);
    final verses = selectedVerses;
    final remove =
        color == null &&
        verses.every((verse) => app.bookmarkFor(verse.id) != null);
    setState(() => savingSelection = true);
    try {
      var message = '收藏已更新';
      if (clearHighlightOnly) {
        for (final verse in verses) {
          await app.clearHighlight(verse);
        }
        message = '已取消高亮';
      } else if (color != null) {
        final cleared = await app.toggleHighlights(verses, color);
        message = cleared ? '已取消高亮' : '已保存高亮';
      } else {
        for (final verse in verses) {
          if (remove) {
            await app.removeBookmark(verse.id);
          } else {
            await app.bookmark(verse);
          }
        }
      }
      if (mounted) {
        clearSelection();
        toast(context, message, brief: true);
      }
    } catch (_) {
      if (mounted) toast(context, '保存失败，请重试');
    } finally {
      if (mounted) setState(() => savingSelection = false);
    }
  }

  Future<void> openVerseNotes(Verse verse) async {
    if (!fullscreen || savingSelection) return;
    if (selecting) clearSelection();
    final noteId = await showVerseNotes(context, verse);
    if (mounted && noteId != null) {
      setFullscreen(false);
      context.push('/note/$noteId');
    }
  }

  Future<void> shareSelected() async {
    if (savingSelection) return;
    final app = ref.read(appProvider);
    final verses = selectedVerses;
    setState(() => savingSelection = true);
    try {
      final shared = await app.shareVerses(verses);
      if (mounted && shared) clearSelection();
    } catch (_) {
      if (mounted) toast(context, '分享或记录保存失败，请重试');
    } finally {
      if (mounted) setState(() => savingSelection = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (pages == null) {
      final positions = ref.read(appProvider).bible.positions;
      current = positions.indexWhere(
        (p) => p.bookCode == widget.bookCode && p.chapter == widget.chapter,
      );
      if (current < 0) {
        current = 0;
      }
      pages = PageController(initialPage: current);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref
            .read(appProvider)
            .recordPosition(
              ChapterPosition(
                positions[current].bookCode,
                positions[current].chapter,
                verse: widget.verse,
              ),
            ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookCode == widget.bookCode &&
        oldWidget.chapter == widget.chapter &&
        oldWidget.verse == widget.verse) {
      return;
    }
    selected.clear();
    final app = ref.read(appProvider);
    final index = app.bible.positions.indexWhere(
      (position) =>
          position.bookCode == widget.bookCode &&
          position.chapter == widget.chapter,
    );
    current = index < 0 ? 0 : index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pages?.hasClients ?? false) pages!.jumpToPage(current);
      app.recordPosition(
        ChapterPosition(
          app.bible.positions[current].bookCode,
          app.bible.positions[current].chapter,
          verse: widget.verse,
        ),
      );
    });
  }

  @override
  void dispose() {
    pages?.dispose();
    if (fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  Future<void> copySelected() async {
    final bible = ref.read(appProvider).bible;
    final list = selectedVerses;
    await Clipboard.setData(
      ClipboardData(text: list.map(bible.copyText).join('\n')),
    );
    if (mounted) {
      toast(context, '已复制 ${list.length} 节经文', brief: true);
      clearSelection();
    }
  }

  Future<void> openCatalog() async {
    final position = ref.read(appProvider).bible.positions[current];
    final chosen = await context.push<ChapterPosition>(
      Uri(
        path: '/catalog',
        queryParameters: {
          'pick': 'true',
          'book': position.bookCode,
          'chapter': '${position.chapter}',
        },
      ).toString(),
    );
    if (mounted && chosen != null) context.pushReplacement(chosen.route);
  }

  void moreTools({bool study = false}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tool in [
              (Icons.edit_note_outlined, '我的笔记', '/notes'),
              (Icons.bookmark_border, '收藏与高亮', '/bookmarks'),
              (Icons.history, '阅读历史', '/history'),
              if (!study)
                (Icons.cloud_download_outlined, '离线与服务连接', '/settings'),
            ])
              ListTile(
                leading: Icon(tool.$1),
                title: Text(tool.$2),
                onTap: () {
                  Navigator.pop(sheet);
                  context.push(tool.$3);
                },
              ),
            if (!study)
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('全屏阅读'),
                onTap: () {
                  Navigator.pop(sheet);
                  setFullscreen(true);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final bible = app.bible;
    final ink = readingInk(context);
    Widget pill(String label, VoidCallback action) => OutlinedButton(
      onPressed: action,
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: ink.withValues(alpha: .3)),
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w300),
      ),
    );
    return PopScope(
      canPop: !selecting && context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || savingSelection) return;
        if (selecting) {
          clearSelection();
        } else {
          backOrHome(context);
        }
      },
      child: Scaffold(
        backgroundColor: readingPaper(context),
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: fullscreen
            ? null
            : AppBar(
                toolbarHeight: 50,
                backgroundColor: readingChrome(context),
                foregroundColor: ink,
                leadingWidth: 78,
                leading: selecting
                    ? IconButton(
                        tooltip: '取消选择',
                        onPressed: savingSelection ? null : clearSelection,
                        icon: const Icon(Icons.close),
                      )
                    : readingBackButton(context, () => backOrHome(context)),
                title: selecting
                    ? Text(
                        '已选 ${selected.length} 节',
                        style: const TextStyle(fontSize: 16),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          pill('目录', openCatalog),
                          const SizedBox(width: 10),
                          pill('和合本', () => showReadingTranslation(context)),
                        ],
                      ),
                actions: [
                  IconButton(
                    tooltip: '阅读历史',
                    onPressed: () => context.push('/history'),
                    icon: const Icon(Icons.history, size: 26),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Divider(
                    height: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
        body: !bible.unlocked
            ? EmptyState(
                icon: Icons.lock_outline,
                title: '正文尚未解锁',
                message: app.connectionError ?? '首次阅读需要联网获取密钥，下载后即可离线阅读。',
                action: FilledButton(
                  onPressed: app.connecting ? null : app.reconnect,
                  child: Text(app.connecting ? '连接中…' : '联网解锁'),
                ),
              )
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: readingTap,
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: pages,
                      itemCount: bible.positions.length,
                      onPageChanged: (value) {
                        setState(() {
                          current = value;
                          selected.clear();
                        });
                        app.recordPosition(bible.positions[value]);
                      },
                      itemBuilder: (context, index) => ChapterView(
                        key: ValueKey(bible.positions[index].key),
                        position: bible.positions[index],
                        targetVerse:
                            bible.positions[index].bookCode ==
                                    widget.bookCode &&
                                bible.positions[index].chapter == widget.chapter
                            ? widget.verse
                            : 1,
                        selected: selected,
                        selectionOpen: selecting,
                        onTap: toggleVerse,
                        onLongPress: selectVerse,
                        onNotesTap: fullscreen ? openVerseNotes : null,
                      ),
                    ),
                    if (selecting)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: SafeArea(
                          top: false,
                          child: Center(child: selectionToolbar(app)),
                        ),
                      ),
                  ],
                ),
              ),
        bottomNavigationBar: fullscreen || selecting
            ? null
            : Container(
                decoration: BoxDecoration(
                  color: readingChrome(context),
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 57,
                    child: Row(
                      children: [
                        _tool(
                          Icons.play_arrow_outlined,
                          '播放',
                          () => toast(context, '朗读功能尚未接入'),
                        ),
                        _tool(
                          Icons.search,
                          '搜索',
                          () => context.push('/search'),
                        ),
                        _tool(
                          Icons.translate,
                          '对照',
                          () => showReadingTranslation(context),
                        ),
                        _tool(
                          Icons.school_outlined,
                          '研读',
                          () => moreTools(study: true),
                        ),
                        _tool(
                          Icons.settings_outlined,
                          '设置',
                          () => readingSettings(context, app),
                        ),
                        _tool(Icons.more_horiz, '更多', moreTools),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget selectionToolbar(AppController app) {
    final allBookmarked = selectedVerses.every(
      (verse) => app.bookmarkFor(verse.id) != null,
    );
    final onlyHighlights = selectedVerses.every(
      (verse) =>
          app.bookmarkFor(verse.id)?['color'] != null &&
          app.noteCountFor(verse.id) == 0,
    );
    return AbsorbPointer(
      absorbing: savingSelection,
      child: GestureDetector(
        onTap: () {},
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Material(
            key: const ValueKey('reader-selection-toolbar'),
            elevation: 12,
            shadowColor: Colors.black38,
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '已选 ${selected.length} 节',
                          style: const TextStyle(fontSize: 12, color: gold),
                        ),
                      ),
                      IconButton(
                        tooltip: '取消选择',
                        onPressed: savingSelection ? null : clearSelection,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _action(Icons.copy_outlined, '复制', copySelected),
                        _action(
                          onlyHighlights
                              ? Icons.format_color_reset
                              : Icons.bookmark_border,
                          onlyHighlights
                              ? '取消高亮'
                              : allBookmarked
                              ? '取消收藏'
                              : '收藏',
                          () =>
                              saveSelection(clearHighlightOnly: onlyHighlights),
                        ),
                        _action(Icons.edit_note, '笔记', openSelectionNote),
                        _action(Icons.ios_share_outlined, '分享', shareSelected),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Text('高亮', style: TextStyle(fontSize: 12)),
                        ),
                        for (final color in highlightColors)
                          HighlightColorButton(
                            color: color,
                            selected: selectedVerses.any(
                              (verse) =>
                                  app.bookmarkFor(verse.id)?['color'] == color,
                            ),
                            onTap: savingSelection
                                ? null
                                : () => saveSelection(color: color),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback action) => Expanded(
    child: InkWell(
      onTap: action,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: readingInk(context)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: readingInk(context)),
          ),
        ],
      ),
    ),
  );
}

const highlightColors = ['#F2D893', '#B9D7BB', '#ACCFDF', '#D5B7CE', '#E8B6A1'];

Future<String?> showVerseNotes(
  BuildContext context,
  Verse verse,
) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheet) => Consumer(
    builder: (context, ref, _) {
      final app = ref.watch(appProvider);
      final notes = app.notesFor(verse.id);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${app.bible.formatReferences([verse])} · ${notes.length} 条笔记',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭笔记',
                    onPressed: () => Navigator.pop(sheet),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: notes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('这节经文暂无笔记'),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(top: 12),
                        itemCount: notes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final note = notes[index];
                          return SurfaceCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (note['title'] as String? ?? '')
                                          .trim()
                                          .isEmpty
                                      ? '未命名笔记'
                                      : note['title'] as String,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  note['content'] as String? ?? '',
                                  style: const TextStyle(height: 1.7),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(
                                      sheet,
                                      note['id'] as String,
                                    ),
                                    child: const Text('编辑笔记'),
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
      );
    },
  ),
);

class HighlightColorButton extends StatelessWidget {
  const HighlightColorButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '高亮颜色 $color',
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? readingAccent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(int.parse(color.replaceFirst('#', 'ff'), radix: 16)),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> verseActions(
  BuildContext context,
  AppController app,
  Verse verse,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${app.bible.book(verse.bookCode).name} ${verse.chapter}:${verse.label}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            verse.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.8),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 4,
            children: [
              _action(
                Icons.bookmark_border,
                app.bookmarkFor(verse.id) == null ? '收藏' : '取消收藏',
                () async {
                  Navigator.pop(sheet);
                  if (app.bookmarkFor(verse.id) == null) {
                    await app.bookmark(verse);
                  } else {
                    await app.removeBookmark(verse.id);
                  }
                  if (context.mounted) {
                    toast(context, '收藏已更新', brief: true);
                  }
                },
              ),
              _action(Icons.edit_note, '笔记', () {
                Navigator.pop(sheet);
                context.push('/note/new?verses=${verse.id}');
              }),
              _action(Icons.copy_outlined, '复制', () async {
                await Clipboard.setData(
                  ClipboardData(text: app.bible.copyText(verse)),
                );
                if (sheet.mounted) {
                  Navigator.pop(sheet);
                }
                if (context.mounted) {
                  toast(context, '经文已复制', brief: true);
                }
              }),
              _action(Icons.ios_share_outlined, '分享', () async {
                Navigator.pop(sheet);
                try {
                  await app.shareVerses([verse]);
                } catch (_) {
                  if (context.mounted) {
                    toast(context, '分享或记录保存失败，请重试');
                  }
                }
              }),
            ],
          ),
          const Divider(height: 28),
          const Text('为这段话语留个印记', style: TextStyle(fontSize: 12, color: gold)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final color in highlightColors)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: HighlightColorButton(
                    color: color,
                    selected: app.bookmarkFor(verse.id)?['color'] == color,
                    onTap: () async {
                      Navigator.pop(sheet);
                      final cleared = await app.toggleHighlights([
                        verse,
                      ], color);
                      if (context.mounted) {
                        toast(
                          context,
                          cleared ? '已取消高亮' : '已保存高亮',
                          brief: true,
                        );
                      }
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  ),
);

Widget _action(IconData icon, String title, VoidCallback onTap) => SizedBox(
  width: 64,
  child: TextButton(
    style: TextButton.styleFrom(foregroundColor: readingAccent),
    onPressed: onTap,
    child: Column(
      children: [
        Icon(icon, size: 22),
        const SizedBox(height: 7),
        Text(title, style: const TextStyle(fontSize: 11)),
      ],
    ),
  ),
);

Future<void> readingSettings(BuildContext context, AppController app) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('阅读设置', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  const Text(
                    'Aa',
                    style: TextStyle(fontSize: 24, color: forest),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('字号'),
                  Expanded(
                    child: Slider(
                      value: app.fontSize,
                      min: 16,
                      max: 32,
                      divisions: 16,
                      label: '${app.fontSize.toInt()}',
                      onChanged: (value) {
                        app.typography(value, app.lineHeight);
                        setState(() {});
                      },
                    ),
                  ),
                  Text('${app.fontSize.toInt()}'),
                ],
              ),
              Row(
                children: [
                  const Text('行距'),
                  Expanded(
                    child: Slider(
                      value: app.lineHeight,
                      min: 1.4,
                      max: 2.4,
                      divisions: 10,
                      onChanged: (value) {
                        app.typography(app.fontSize, value);
                        setState(() {});
                      },
                    ),
                  ),
                  Text(app.lineHeight.toStringAsFixed(1)),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('夜间阅读'),
                value: app.dark,
                onChanged: (value) {
                  app.theme(value);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );

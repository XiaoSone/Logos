import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/bible_models.dart';
import '../state/app_controller.dart';
import 'design.dart';
import 'reading_style.dart';

class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({
    super.key,
    this.initialPosition,
    this.pickOnly = false,
    this.selectVerses = false,
    this.initialVerseIds = const [],
    this.maxSelection = 100,
  });
  final ChapterPosition? initialPosition;
  final bool pickOnly;
  final bool selectVerses;
  final List<String> initialVerseIds;
  final int maxSelection;

  @override
  ConsumerState<CatalogPage> createState() => _CatalogState();
}

class _CatalogState extends ConsumerState<CatalogPage> {
  Book? book;
  int chapter = 1;
  int tab = 0;
  int testament = 1;
  bool toVerse = true;
  bool grid = true;
  final oldKey = GlobalKey();
  final newKey = GlobalKey();
  late final selected = widget.initialVerseIds.toSet();

  void confirmSelection() {
    final bible = ref.read(appProvider).bible;
    Navigator.pop(context, [
      for (final verse in bible.verses)
        if (selected.contains(verse.id)) verse.id,
      ...selected.where((id) => !bible.byId.containsKey(id)),
    ]);
  }

  void toggleSelection(Verse verse) {
    final group = ref
        .read(appProvider)
        .bible
        .chapter(ChapterPosition(verse.bookCode, verse.chapter))
        .where((item) => item.bridgeStart == verse.bridgeStart)
        .map((item) => item.id)
        .toSet();
    final remove = group.any(selected.contains);
    if (!remove && {...selected, ...group}.length > widget.maxSelection) {
      toast(context, '最多可关联 ${widget.maxSelection} 节经文');
      return;
    }
    setState(() => remove ? selected.removeAll(group) : selected.addAll(group));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (book != null) return;
    final app = ref.read(appProvider);
    final position = widget.initialPosition ?? app.last;
    book = app.bible.tryBook(position.bookCode) ?? app.bible.books.firstOrNull;
    chapter = position.chapter.clamp(1, book?.chapters ?? 1);
    testament = book?.testament ?? 1;
    if (testament == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scrollTestament(2);
      });
    }
  }

  void scrollTestament(int value) {
    setState(() => testament = value);
    final target = value == 1 ? oldKey.currentContext : newKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 220),
        alignment: 0,
      );
    }
  }

  void open(int verse) {
    final position = ChapterPosition(book!.code, chapter, verse: verse);
    if (widget.pickOnly && context.canPop()) {
      context.pop(position);
    } else {
      context.pushReplacement(position.route);
    }
  }

  void chooseBook(Book value) => setState(() {
    if (book?.code != value.code) chapter = 1;
    book = value;
    testament = value.testament;
    tab = 1;
  });

  @override
  Widget build(BuildContext context) {
    final bible = ref.watch(appProvider).bible;
    final ink = readingInk(context);
    return Scaffold(
      backgroundColor:
          tab == 0 || Theme.of(context).brightness == Brightness.dark
          ? readingPaper(context)
          : const Color(0xfff1f2f5),
      appBar: AppBar(
        backgroundColor: readingChrome(context),
        foregroundColor: ink,
        toolbarHeight: 52,
        leadingWidth: 78,
        leading: readingBackButton(
          context,
          () => widget.selectVerses
              ? Navigator.pop(context)
              : context.canPop()
              ? context.pop()
              : context.go('/home'),
        ),
        actions: [
          if (widget.selectVerses)
            TextButton(
              onPressed: confirmSelection,
              style: TextButton.styleFrom(foregroundColor: readingAccent),
              child: const Text('确定'),
            ),
        ],
        title: widget.selectVerses
            ? Text(
                tab == 0 || book == null
                    ? '添加经文'
                    : tab == 1
                    ? book!.name
                    : '${book!.name} $chapter',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                ),
              )
            : Column(
                children: [
                  Text(
                    tab == 0 || book == null
                        ? '圣经目录'
                        : '${book!.name} $chapter',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  InkWell(
                    onTap: () => showReadingTranslation(context),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '和合本',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Theme.of(context).dividerColor),
        ),
      ),
      body: book == null
          ? const EmptyState(
              icon: Icons.menu_book,
              title: '目录暂不可用',
              message: '请先完成经文目录加载。',
            )
          : Column(
              children: [
                Container(
                  color: readingChrome(context),
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => tab = i),
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        ['卷', '章', '节'][i],
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w300,
                                          color: tab == i ? readingAccent : ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: widget.selectVerses ? 1 : .62,
                                    child: Container(
                                      height: 2,
                                      color: tab == i
                                          ? readingAccent
                                          : Colors.transparent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (tab == 0)
                  Container(
                    height: 51,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: readingChrome(context),
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!widget.selectVerses) ...[
                          Text(
                            '目录到节',
                            style: TextStyle(fontSize: 12, color: ink),
                          ),
                          Transform.scale(
                            scale: .85,
                            child: Switch(
                              value: toVerse,
                              activeThumbColor: Colors.white,
                              activeTrackColor: readingAccent,
                              onChanged: (value) =>
                                  setState(() => toVerse = value),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text('视图', style: TextStyle(fontSize: 12, color: ink)),
                        IconButton(
                          tooltip: '网格视图',
                          onPressed: () => setState(() => grid = true),
                          icon: Icon(
                            Icons.grid_view_rounded,
                            color: grid ? readingAccent : ink,
                          ),
                        ),
                        IconButton(
                          tooltip: '列表视图',
                          onPressed: () => setState(() => grid = false),
                          icon: Icon(
                            Icons.menu,
                            color: grid ? ink : readingAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: tab == 0
                      ? SingleChildScrollView(
                          key: const PageStorageKey('catalog-books'),
                          child: Column(
                            children: [
                              for (final value in [1, 2]) ...[
                                Container(
                                  key: value == 1 ? oldKey : newKey,
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    value == 1 ? '旧约' : '新约',
                                    style: TextStyle(color: ink, fontSize: 12),
                                  ),
                                ),
                                if (grid)
                                  GridView.count(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    crossAxisCount: 4,
                                    childAspectRatio: 1.2,
                                    children: [
                                      for (final item in bible.books.where(
                                        (b) => b.testament == value,
                                      ))
                                        bookCell(item),
                                    ],
                                  )
                                else
                                  for (final item in bible.books.where(
                                    (b) => b.testament == value,
                                  ))
                                    ListTile(
                                      onTap: () => chooseBook(item),
                                      leading: SizedBox(
                                        width: 45,
                                        child: Text(
                                          item.abbr,
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: item.code == book!.code
                                                ? readingAccent
                                                : ink,
                                          ),
                                        ),
                                      ),
                                      title: Text(item.name),
                                      trailing: Text('${item.chapters} 章'),
                                    ),
                              ],
                            ],
                          ),
                        )
                      : widget.selectVerses && tab == 2
                      ? referenceVerses()
                      : GridView.builder(
                          key: ValueKey('${book!.code}.$tab.$chapter.$grid'),
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                                childAspectRatio: 1.29,
                              ),
                          itemCount: tab == 1
                              ? book!.chapters
                              : bible.chapterSize(
                                  ChapterPosition(book!.code, chapter),
                                ),
                          itemBuilder: (_, index) => InkWell(
                            onTap: () {
                              if (tab == 2) {
                                open(index + 1);
                              } else {
                                setState(() => chapter = index + 1);
                                if (toVerse || widget.selectVerses) {
                                  setState(() => tab = 2);
                                } else {
                                  open(1);
                                }
                              }
                            },
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: readingChrome(context),
                                border: Border.all(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(context).dividerColor
                                      : const Color(0xfff2f2f2),
                                  width: .35,
                                ),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1,
                                  fontWeight: FontWeight.w300,
                                  color:
                                      widget.selectVerses &&
                                          tab == 1 &&
                                          index + 1 == chapter
                                      ? readingAccent
                                      : ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
      bottomNavigationBar: book == null || tab != 0
          ? null
          : SafeArea(
              top: false,
              child: Container(
                color: readingChrome(context),
                height: 52,
                child: Row(
                  children: [
                    for (final value in [1, 2])
                      Expanded(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            shape: const RoundedRectangleBorder(),
                            backgroundColor: testament == value
                                ? readingPaper(context)
                                : readingChrome(context),
                          ),
                          onPressed: () => scrollTestament(value),
                          child: Center(
                            child: Text(
                              value == 1 ? '旧约' : '新约',
                              style: TextStyle(
                                color: testament == value ? readingAccent : ink,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget referenceVerses() {
    final bible = ref.watch(appProvider).bible;
    final verses = bible.visibleChapter(ChapterPosition(book!.code, chapter));
    if (verses.isEmpty) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: '正文尚未解锁',
        message: '请先联网解锁正文，再选择关联经文。',
      );
    }
    return ListTileTheme(
      data: ListTileTheme.of(context).copyWith(
        minTileHeight: 44,
        minVerticalPadding: 3,
        horizontalTitleGap: 4,
      ),
      child: ListView.builder(
        key: ValueKey('note-reference-verses-${book!.code}.$chapter'),
        padding: const EdgeInsets.only(top: 2, bottom: 20),
        itemCount: verses.length,
        itemBuilder: (context, index) {
          final verse = verses[index];
          final checked = bible
              .chapter(ChapterPosition(verse.bookCode, verse.chapter))
              .any(
                (item) =>
                    item.bridgeStart == verse.bridgeStart &&
                    selected.contains(item.id),
              );
          return CheckboxListTile(
            key: ValueKey('note-reference-${verse.id}'),
            value: checked,
            onChanged: (_) => toggleSelection(verse),
            activeColor: readingAccent,
            controlAffinity: ListTileControlAffinity.trailing,
            titleAlignment: ListTileTitleAlignment.top,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: verse.label.length > 2 ? 38 : 24,
                  child: Text(
                    verse.label,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.8,
                      color: readingInk(context),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    verse.text,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.7,
                      color: readingInk(context),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget bookCell(Book item) {
    final color = item.code == book!.code ? readingAccent : readingInk(context);
    return Semantics(
      button: true,
      selected: item.code == book!.code,
      label: item.name,
      child: InkWell(
        onTap: () => chooseBook(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: readingChrome(context).withValues(alpha: .65),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: .25),
              width: .5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.abbr,
                style: TextStyle(
                  fontSize: 20,
                  color: color,
                  height: 1.2,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

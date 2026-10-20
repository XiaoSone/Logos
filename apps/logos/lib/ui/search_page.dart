import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/bible_models.dart';
import '../state/app_controller.dart';
import 'design.dart';
import 'reader.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initial = ''});
  final String initial;
  @override
  ConsumerState<SearchPage> createState() => _SearchState();
}

class _SearchState extends ConsumerState<SearchPage> {
  late final TextEditingController text = TextEditingController(
    text: widget.initial,
  );
  String query = '';
  int? testament;
  String? bookCode;
  int limit = 30;
  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => submit(widget.initial),
      );
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void submit(String value) {
    FocusScope.of(context).unfocus();
    setState(() {
      query = value.trim();
      limit = 30;
    });
    ref.read(appProvider).addSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final result = app.bible.search(
      query,
      testament: testament,
      bookCode: bookCode,
    );
    final visible = result.take(limit).toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => backOrHome(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('搜索经文'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: TextField(
                  controller: text,
                  autofocus: widget.initial.isEmpty,
                  maxLength: 100,
                  textInputAction: TextInputAction.search,
                  onSubmitted: submit,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '关键词或经文引用，如 约 3:16',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      onPressed: () => submit(text.text),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    const Chip(
                      label: Text('精确搜索'),
                      avatar: Icon(Icons.check, size: 14),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '语义搜索 · Phase 2',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                    const Spacer(),
                    if (app.bible.offlineReady)
                      const Icon(
                        Icons.offline_pin_outlined,
                        color: forest,
                        size: 17,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (query.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    children: [
                      DropdownButton<int>(
                        value: testament ?? 0,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('全部经文')),
                          DropdownMenuItem(value: 1, child: Text('旧约')),
                          DropdownMenuItem(value: 2, child: Text('新约')),
                        ],
                        onChanged: (v) => setState(() {
                          testament = v == 0 ? null : v;
                          bookCode = null;
                          limit = 30;
                        }),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButton<String>(
                          value: bookCode ?? '',
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('全部书卷'),
                            ),
                            for (final b in app.bible.books.where(
                              (b) =>
                                  testament == null || b.testament == testament,
                            ))
                              DropdownMenuItem(
                                value: b.code,
                                child: Text(
                                  b.name,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            bookCode = v == '' ? null : v;
                            limit = 30;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '「$query」',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: forest,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${result.length} 条结果',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: !app.bible.unlocked
                    ? EmptyState(
                        icon: Icons.cloud_download_outlined,
                        title: '经文尚未解锁',
                        message: '联网解锁或下载经文后，即可进行完整搜索。',
                        action: FilledButton(
                          onPressed: app.reconnect,
                          child: const Text('连接服务'),
                        ),
                      )
                    : query.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(22),
                        children: [
                          Row(
                            children: [
                              Text(
                                '最近搜索',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              if (app.searchHistory.isNotEmpty)
                                TextButton(
                                  onPressed: app.clearSearch,
                                  child: const Text('清空'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (app.searchHistory.isEmpty)
                            const Text(
                              '试试一个词，或一段经文的地址。',
                              style: TextStyle(color: gold, fontSize: 13),
                            ),
                          Wrap(
                            spacing: 9,
                            runSpacing: 9,
                            children: [
                              for (final q in app.searchHistory)
                                ActionChip(
                                  label: Text(q),
                                  onPressed: () {
                                    text.text = q;
                                    submit(q);
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 35),
                          Text(
                            '从这里开始',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 15),
                          Wrap(
                            spacing: 9,
                            runSpacing: 9,
                            children: [
                              for (final q in [
                                '神爱世人',
                                '信心',
                                '平安',
                                '诗23:1-6',
                                '约1:1',
                              ])
                                ActionChip(
                                  label: Text(q),
                                  onPressed: () {
                                    text.text = q;
                                    submit(q);
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          const Text(
                            '支持中文书名、缩写、英文名与 OSIS 码。\n例如：创1:1、John 3:16、PS 23:1-6。',
                            style: TextStyle(fontSize: 12, color: gold),
                          ),
                        ],
                      )
                    : result.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off,
                        title: '这次没有找到',
                        message: '试试缩短关键词，或检查书卷和章节。\n精确搜索按连续文字片段匹配。',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
                        itemCount:
                            visible.length + (result.length > limit ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == visible.length) {
                            return TextButton(
                              onPressed: () => setState(() => limit += 30),
                              child: Text(
                                '继续显示 · 还剩 ${result.length - limit} 条',
                              ),
                            );
                          }
                          final verse = visible[index];
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
                                    Text(
                                      '${app.bible.book(verse.bookCode).name} ${verse.chapter}:${verse.label}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: forest,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Icon(
                                      Icons.arrow_outward,
                                      size: 16,
                                      color: gold,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 13),
                                Text.rich(
                                  TextSpan(
                                    children: highlight(verse.text, query),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    height: 1.9,
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

List<TextSpan> highlight(String text, String query) {
  if (query.isEmpty) {
    return [TextSpan(text: text)];
  }
  final output = <TextSpan>[];
  var cursor = 0;
  final lower = text.toLowerCase();
  final target = query.toLowerCase();
  while (true) {
    final index = lower.indexOf(target, cursor);
    if (index < 0) {
      output.add(TextSpan(text: text.substring(cursor)));
      break;
    }
    if (index > cursor) {
      output.add(TextSpan(text: text.substring(cursor, index)));
    }
    output.add(
      TextSpan(
        text: text.substring(index, index + query.length),
        style: const TextStyle(
          backgroundColor: Color(0xffe8d8a7),
          color: Color(0xff263e30),
        ),
      ),
    );
    cursor = index + query.length;
  }
  return output;
}

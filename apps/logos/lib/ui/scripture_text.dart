import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/bible_models.dart';
import '../state/app_controller.dart';
import 'reading_style.dart';

class ChapterView extends ConsumerStatefulWidget {
  const ChapterView({
    super.key,
    required this.position,
    required this.targetVerse,
    required this.selected,
    required this.selectionOpen,
    required this.onTap,
    required this.onLongPress,
    this.onNotesTap,
  });
  final ChapterPosition position;
  final int targetVerse;
  final Set<String> selected;
  final bool selectionOpen;
  final ValueChanged<Verse> onTap;
  final ValueChanged<Verse> onLongPress;
  final ValueChanged<Verse>? onNotesTap;

  @override
  ConsumerState<ChapterView> createState() => _ChapterState();
}

class _ChapterState extends ConsumerState<ChapterView> {
  final scroll = ScrollController();
  final viewport = GlobalKey();
  final paragraphs = <String, GlobalKey<ScriptureParagraphState>>{};
  bool positioned = false;

  @override
  void didUpdateWidget(covariant ChapterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetVerse != widget.targetVerse) {
      positioned = false;
      if (widget.targetVerse <= 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) scroll.jumpTo(0);
        });
      }
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void positionTarget(List<Verse> verses) {
    if (positioned || verses.isEmpty) return;
    positioned = true;
    if (widget.targetVerse <= 1) return;
    final target = verses.lastWhere(
      (v) => v.number <= widget.targetVerse,
      orElse: () => verses.first,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final point = paragraphs[target.sectionId]?.currentState?.versePoint(
        target.id,
      );
      final box = viewport.currentContext?.findRenderObject() as RenderBox?;
      if (point == null || box == null) return;
      final top = box.localToGlobal(Offset.zero).dy;
      final destination = scroll.offset + point.dy - top - 112;
      scroll.jumpTo(destination.clamp(0, scroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final bible = app.bible;
    final verses = bible.visibleChapter(widget.position);
    final groups = <List<Verse>>[];
    for (final verse in verses) {
      if (groups.isEmpty || groups.last.first.sectionId != verse.sectionId) {
        groups.add([]);
      }
      groups.last.add(verse);
    }
    positionTarget(verses);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          key: viewport,
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            24,
            42,
            24,
            widget.selectionOpen ? 260 : 96,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 19),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${bible.book(widget.position.bookCode).name}    ${widget.position.chapter}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: readingAccent,
                        ),
                      ),
                    ),
                    const Text(
                      '和合本',
                      style: TextStyle(fontSize: 13, color: readingAccent),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < groups.length; i++) ...[
                if (bible.sections[groups[i]
                        .first
                        .sectionId]?['sectionTitle'] !=
                    null)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 20, bottom: 6),
                    child: Text(
                      bible.sections[groups[i].first.sectionId]!['sectionTitle']
                          as String,
                      style: TextStyle(
                        fontSize: 16,
                        color: readingInk(context),
                        height: 1.6,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ScriptureParagraph(
                  key: paragraphs.putIfAbsent(
                    groups[i].first.sectionId,
                    () => GlobalKey<ScriptureParagraphState>(),
                  ),
                  verses: groups[i],
                  chapter: i == 0 ? widget.position.chapter : null,
                  selected: widget.selected,
                  onTap: widget.onTap,
                  onLongPress: widget.onLongPress,
                  onNotesTap: widget.onNotesTap,
                ),
                if (groups[i].any((v) => v.footnotes.isNotEmpty))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: readingInk(context),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: const Text('经文脚注'),
                          content: SingleChildScrollView(
                            child: Text(
                              [
                                for (final verse in groups[i])
                                  for (final note in verse.footnotes)
                                    '${verse.label}　${note['content']}',
                              ].join('\n\n'),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.info_outline, size: 13),
                      label: const Text('脚注', style: TextStyle(fontSize: 11)),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ScriptureParagraph extends ConsumerStatefulWidget {
  const ScriptureParagraph({
    super.key,
    required this.verses,
    this.chapter,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.onNotesTap,
  });
  final List<Verse> verses;
  final int? chapter;
  final Set<String> selected;
  final ValueChanged<Verse> onTap;
  final ValueChanged<Verse> onLongPress;
  final ValueChanged<Verse>? onNotesTap;

  @override
  ConsumerState<ScriptureParagraph> createState() => ScriptureParagraphState();
}

class ScriptureParagraphState extends ConsumerState<ScriptureParagraph> {
  final firstKey = GlobalKey();
  final restKey = GlobalKey();
  final taps = <String, TapGestureRecognizer>{};
  final noteTaps = <String, TapGestureRecognizer>{};
  final ranges = <({Verse verse, int start, int body, int end})>[];
  final marks = <ScriptureMark>[];
  int split = 0;

  @override
  void dispose() {
    for (final tap in taps.values) {
      tap.dispose();
    }
    for (final tap in noteTaps.values) {
      tap.dispose();
    }
    super.dispose();
  }

  Offset? versePoint(String id) {
    final range = ranges.where((range) => range.verse.id == id).firstOrNull;
    if (range == null) return null;
    final key = range.body < split ? firstKey : restKey;
    final base = range.body < split ? 0 : split;
    final render = key.currentContext?.findRenderObject() as RenderParagraph?;
    if (render == null) return null;
    final boxes = render.getBoxesForSelection(
      TextSelection(
        baseOffset: range.body - base,
        extentOffset: math.min(range.end, range.body + 1) - base,
      ),
    );
    if (boxes.isEmpty) return null;
    return render.localToGlobal(Offset(boxes.first.left, boxes.first.top));
  }

  ScriptureMarksPainter markPainter(GlobalKey key, int base, int limit) =>
      ScriptureMarksPainter(
        textKey: key,
        base: base,
        limit: limit,
        marks: List.of(marks),
        fontSize: MediaQuery.textScalerOf(
          context,
        ).scale(ref.read(appProvider).fontSize),
      );

  Rect? noteBadgeBounds(String id) {
    final mark = marks.where((mark) => mark.verseId == id).firstOrNull;
    if (mark == null) return null;
    for (final part in [
      (firstKey, 0, split),
      (restKey, split, ranges.last.end),
    ]) {
      final layout = markPainter(part.$1, part.$2, part.$3).badgeLayout(mark);
      final render =
          part.$1.currentContext?.findRenderObject() as RenderParagraph?;
      if (layout != null && render != null) {
        return Rect.fromCircle(
          center: render.localToGlobal(layout.center),
          radius: math.max(12, layout.radius + 4),
        );
      }
    }
    return null;
  }

  Offset? noteBadgePoint(String id) => noteBadgeBounds(id)?.center;

  String? hitNote(Offset global) {
    if (widget.onNotesTap == null || ranges.isEmpty) return null;
    for (final mark in marks.where((mark) => mark.noteCount > 0)) {
      final bounds = noteBadgeBounds(mark.verseId);
      if (bounds != null &&
          (bounds.center - global).distance <= bounds.width / 2) {
        return mark.verseId;
      }
    }
    return null;
  }

  void longPress(GlobalKey key, int base, Offset point) {
    final render = key.currentContext?.findRenderObject() as RenderParagraph?;
    if (render == null) return;
    final offset =
        render.getPositionForOffset(render.globalToLocal(point)).offset + base;
    final range = ranges
        .where((range) => offset >= range.start && offset < range.end)
        .firstOrNull;
    if (range != null) widget.onLongPress(range.verse);
  }

  List<TextSpan> slice(List<TextSpan> spans, int start, int end) {
    var offset = 0;
    final result = <TextSpan>[];
    for (final span in spans) {
      final text = span.text!;
      final left = math.max(start - offset, 0);
      final right = math.min(end - offset, text.length);
      if (left < right) {
        result.add(
          TextSpan(
            text: text.substring(left, right),
            style: span.style,
            recognizer: span.recognizer,
            semanticsLabel: span.semanticsLabel,
          ),
        );
      }
      offset += text.length;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final style = TextStyle(
      color: readingInk(context),
      fontSize: app.fontSize,
      height: app.lineHeight,
      letterSpacing: .25,
      fontFamily: 'sans-serif',
      fontWeight: FontWeight.w300,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final spans = <TextSpan>[];
    ranges.clear();
    marks.clear();
    var offset = 0;
    for (final verse in widget.verses) {
      final tap = taps.putIfAbsent(verse.id, TapGestureRecognizer.new)
        ..onTap = () => widget.onTap(verse);
      final prefix =
          widget.chapter != null &&
              verse == widget.verses.first &&
              verse.label == '1'
          ? ''
          : ' ${verse.label} ';
      final start = offset;
      spans.add(
        TextSpan(
          text: prefix,
          style: TextStyle(fontSize: app.fontSize * .6),
          recognizer: tap,
        ),
      );
      offset += prefix.length;
      final body = offset;
      final color = app.bookmarkFor(verse.id)?['color'] as String?;
      spans.add(
        TextSpan(
          text: verse.text,
          recognizer: tap,
          style: TextStyle(
            backgroundColor: color == null
                ? null
                : Color(
                    int.parse(color.replaceFirst('#', 'ff'), radix: 16),
                  ).withValues(alpha: app.dark ? .28 : .48),
            decoration: widget.selected.contains(verse.id)
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationStyle: TextDecorationStyle.dashed,
            decorationColor: readingAccent,
            decorationThickness: 1.25,
          ),
        ),
      );
      offset += verse.text.length;
      final bodyEnd = offset;
      final noteCount = app.noteCountFor(verse.id);
      if (noteCount > 0) {
        final noteTap = noteTaps.putIfAbsent(verse.id, TapGestureRecognizer.new)
          ..onTap = () => widget.onNotesTap != null
              ? widget.onNotesTap!(verse)
              : widget.onTap(verse);
        spans.add(
          TextSpan(
            text: '\u2003',
            style: TextStyle(
              fontSize:
                  app.fontSize *
                  math.max(.8, noteCount.toString().length * .3 + .35),
            ),
            recognizer: noteTap,
            semanticsLabel: '（$noteCount 条笔记）',
          ),
        );
        offset++;
      }
      if (noteCount > 0 ||
          (app.bookmarkFor(verse.id) != null && color == null)) {
        marks.add(
          ScriptureMark(
            verseId: verse.id,
            start: body,
            end: bodyEnd,
            noteCount: noteCount,
          ),
        );
      }
      ranges.add((verse: verse, start: start, body: body, end: offset));
    }
    final length = offset;
    Widget textPart(GlobalKey key, int start, int end) => GestureDetector(
      onLongPressStart: (details) =>
          longPress(key, start, details.globalPosition),
      child: _NoteBadgeHitRegion(
        hitNote: hitNote,
        onNotesTap: (id) => widget.onNotesTap?.call(
          widget.verses.firstWhere((verse) => verse.id == id),
        ),
        child: CustomPaint(
          foregroundPainter: markPainter(key, start, end),
          child: RichText(
            key: key,
            textAlign: TextAlign.justify,
            textScaler: scaler,
            text: TextSpan(style: style, children: slice(spans, start, end)),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.chapter == null) {
          split = 0;
          return textPart(restKey, 0, length);
        }
        final capStyle = style.copyWith(
          fontSize: app.fontSize * 3,
          height: 1.05,
        );
        final cap = TextPainter(
          text: TextSpan(text: '${widget.chapter}', style: capStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final capWidth = math.min(cap.width + 3, constraints.maxWidth * .36);
        cap.dispose();
        final painter = TextPainter(
          text: TextSpan(style: style, children: spans),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: constraints.maxWidth - capWidth);
        final lines = painter.computeLineMetrics();
        split = length;
        if (lines.length > 2) {
          final line = lines[1];
          split = painter
              .getPositionForOffset(
                Offset(
                  constraints.maxWidth - capWidth,
                  line.baseline - line.ascent / 2,
                ),
              )
              .offset;
        }
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => widget.onTap(widget.verses.first),
                  onLongPress: () => widget.onLongPress(widget.verses.first),
                  child: SizedBox(
                    width: capWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: Text('${widget.chapter}', style: capStyle),
                    ),
                  ),
                ),
                Expanded(child: textPart(firstKey, 0, split)),
              ],
            ),
            if (split < length) textPart(restKey, split, length),
          ],
        );
      },
    );
  }
}

class ScriptureMark {
  const ScriptureMark({
    required this.verseId,
    required this.start,
    required this.end,
    required this.noteCount,
  });
  final String verseId;
  final int start;
  final int end;
  final int noteCount;
}

class ScriptureMarksPainter extends CustomPainter {
  ScriptureMarksPainter({
    required this.textKey,
    required this.base,
    required this.limit,
    required this.marks,
    required this.fontSize,
  });
  final GlobalKey textKey;
  final int base;
  final int limit;
  final List<ScriptureMark> marks;
  final double fontSize;

  TextPainter badgeText(ScriptureMark mark) => TextPainter(
    text: TextSpan(
      text: '${mark.noteCount}',
      style: TextStyle(
        fontSize: fontSize * .46,
        fontFamily: 'sans-serif',
        color: readingAccent,
        fontWeight: FontWeight.w500,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  ({Offset center, double radius})? badgeLayout(ScriptureMark mark) {
    if (mark.noteCount == 0 || mark.end < base || mark.end >= limit) {
      return null;
    }
    final render =
        textKey.currentContext?.findRenderObject() as RenderParagraph?;
    if (render == null) return null;
    final boxes = render.getBoxesForSelection(
      TextSelection(
        baseOffset: mark.end - base,
        extentOffset: mark.end + 1 - base,
      ),
    );
    if (boxes.isEmpty) return null;
    final text = badgeText(mark);
    final radius = math.max(fontSize * .32, text.width / 2 + 3);
    text.dispose();
    return (
      center: Offset(boxes.first.left + radius + 1, boxes.first.bottom + 2),
      radius: radius,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final render =
        textKey.currentContext?.findRenderObject() as RenderParagraph?;
    if (render == null) return;
    final pen = Paint()
      ..color = readingAccent
      ..strokeWidth = 1.1;
    for (final mark in marks) {
      final start = math.max(mark.start, base);
      final end = math.min(mark.end, limit);
      if (start < end) {
        for (final box in render.getBoxesForSelection(
          TextSelection(baseOffset: start - base, extentOffset: end - base),
        )) {
          // The native dashed selection underline sits above this solid track.
          final y = box.bottom + 2;
          canvas.drawLine(Offset(box.left, y), Offset(box.right, y), pen);
        }
      }
      final layout = badgeLayout(mark);
      if (layout == null) continue;
      final text = badgeText(mark);
      final center = layout.center;
      canvas.drawCircle(
        center,
        layout.radius,
        Paint()
          ..color = readingAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant ScriptureMarksPainter oldDelegate) => true;
}

class _NoteBadgeHitRegion extends SingleChildRenderObjectWidget {
  const _NoteBadgeHitRegion({
    required this.hitNote,
    required this.onNotesTap,
    required super.child,
  });
  final String? Function(Offset) hitNote;
  final ValueChanged<String> onNotesTap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNoteBadgeHitRegion(hitNote, onNotesTap);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderNoteBadgeHitRegion renderObject,
  ) {
    renderObject
      ..hitNote = hitNote
      ..onNotesTap = onNotesTap;
  }
}

class _RenderNoteBadgeHitRegion extends RenderProxyBox {
  _RenderNoteBadgeHitRegion(this.hitNote, this.onNotesTap);
  String? Function(Offset) hitNote;
  ValueChanged<String> onNotesTap;
  final tap = TapGestureRecognizer();

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      hitNote(localToGlobal(position)) == null &&
      super.hitTestChildren(result, position: position);

  @override
  bool hitTestSelf(Offset position) => hitNote(localToGlobal(position)) != null;

  @override
  void handleEvent(PointerEvent event, covariant HitTestEntry entry) {
    if (event is PointerDownEvent) {
      final id = hitNote(event.position);
      if (id != null) {
        tap.onTap = () => onNotesTap(id);
        tap.addPointer(event);
      }
    }
  }

  @override
  void dispose() {
    tap.dispose();
    super.dispose();
  }
}

class Book {
  const Book(this.json);
  final Map<String, dynamic> json;
  String get code => json['bookCode'] as String;
  String get name => json['bookNameZh'] as String;
  String get abbr => json['bookNameAbbr'] as String;
  String get english => json['bookNameEn'] as String;
  int get chapters => json['chapterCount'] as int;
  int get order => json['bookOrder'] as int;
  int get testament => json['testament'] as int;
  List<String> get aliases => (json['aliases'] as List).cast<String>();
}

class Verse {
  const Verse(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'].toString();
  String get bookCode => json['bookCode'] as String;
  int get chapter => json['chapter'] as int;
  int get number => json['verse'] as int;
  String get text => json['textZh'] as String;
  String get label => json['verseLabel'] as String? ?? '$number';
  int get bridgeStart => json['bridgeStart'] as int? ?? number;
  String get ref => json['verseRef'] as String;
  String get sectionId => json['sectionId'] as String;
  List<Map<String, dynamic>> get footnotes =>
      ((json['footnotes'] as List?) ?? []).cast<Map<String, dynamic>>();
}

class ChapterPosition {
  const ChapterPosition(this.bookCode, this.chapter, {this.verse = 1});
  final String bookCode;
  final int chapter;
  final int verse;
  String get route => '/read/$bookCode/$chapter?verse=$verse';
  String get key => '$bookCode.$chapter';
}

String normalizeQuery(String value) {
  return value
      .replaceAllMapped(
        RegExp('[０-９]'),
        (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xfee0),
      )
      .replaceAll('：', ':')
      .replaceAll('　', ' ')
      .trim();
}

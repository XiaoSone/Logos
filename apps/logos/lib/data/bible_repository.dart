import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:uuid/uuid.dart';
import 'bible_models.dart';
import 'local_store.dart';

class BibleRepository {
  BibleRepository(this.store);
  final LocalStore store;
  static const secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _aes = AesGcm.with256bits();
  List<Book> books = [];
  List<Verse> verses = [];
  List<ChapterPosition> positions = [];
  Map<String, Map<String, dynamic>> sections = {};
  Map<String, Verse> byId = {};
  Map<String, List<Verse>> byChapter = {};
  List<Map<String, dynamic>> chapterIndex = [];
  String deviceId = '';
  String guestToken = '';
  String server = const String.fromEnvironment('API_URL', defaultValue: '');
  bool offlineReady = false;
  bool get unlocked => verses.isNotEmpty;

  Future<void> initialize() async {
    final index =
        jsonDecode(await rootBundle.loadString('assets/bible_index.json'))
            as Map<String, dynamic>;
    books = (index['books'] as List)
        .map((b) => Book(b as Map<String, dynamic>))
        .toList();
    sections = {
      for (final s in index['sections'] as List)
        s['id'] as String: s as Map<String, dynamic>,
    };
    chapterIndex = (index['chapters'] as List).cast<Map<String, dynamic>>();
    positions = [
      for (final b in books)
        for (var c = 1; c <= b.chapters; c++) ChapterPosition(b.code, c),
    ];
    deviceId = await store.setting('deviceId') ?? const Uuid().v4();
    await store.setSetting('deviceId', deviceId);
    server =
        await store.setting('server') ??
        (server.isNotEmpty
            ? server
            : kIsWeb
            ? 'http://127.0.0.1:8080/graphql'
            : 'http://10.0.2.2:8080/graphql');
    final cached = await store.setting('device.bin');
    final deviceKey = await secure.read(key: 'bible_device_key');
    if (cached != null && deviceKey != null) {
      try {
        _load(await decrypt(base64Decode(cached), deviceKey));
        offlineReady = true;
      } on SecretBoxAuthenticationError {
        await store.removeSetting('device.bin');
        await secure.delete(key: 'bible_device_key');
      }
    }
  }

  GraphQLClient get client => GraphQLClient(
    link: HttpLink(
      server,
      defaultHeaders: {
        if (guestToken.isNotEmpty) 'Authorization': 'Bearer $guestToken',
      },
    ),
    cache: GraphQLCache(store: InMemoryStore()),
  );

  Future<Map<String, dynamic>> execute(
    String document, {
    Map<String, dynamic> variables = const {},
    bool mutation = false,
  }) async {
    final result = mutation
        ? await client
              .mutate(
                MutationOptions(
                  document: gql(document),
                  variables: variables,
                  fetchPolicy: FetchPolicy.noCache,
                ),
              )
              .timeout(const Duration(seconds: 15))
        : await client
              .query(
                QueryOptions(
                  document: gql(document),
                  variables: variables,
                  fetchPolicy: FetchPolicy.noCache,
                ),
              )
              .timeout(const Duration(seconds: 15));
    if (result.hasException) {
      final errors = result.exception!.graphqlErrors;
      throw StateError(
        errors.isEmpty ? '暂时无法连接服务，请检查服务地址或网络。' : errors.first.message,
      );
    }
    return result.data!;
  }

  /// Structure metadata is enough to sync references before decrypting any text.
  String referenceForId(String id) {
    final value = int.tryParse(id);
    if (value == null) throw ArgumentError('无效经文 ID');
    final order = value ~/ 1000000;
    final chapter = value % 1000000 ~/ 1000;
    final verse = value % 1000;
    final found = books.where((book) => book.order == order).firstOrNull;
    if (found == null ||
        chapter < 1 ||
        chapter > found.chapters ||
        verse < 1 ||
        verse > 176) {
      throw ArgumentError('无效经文 ID');
    }
    return '${found.code} $chapter:$verse';
  }

  Future<void> connect() async {
    final result = await execute(
      r'mutation($id:String!){issueGuestToken(deviceId:$id){token}}',
      variables: {'id': deviceId},
      mutation: true,
    );
    guestToken = result['issueGuestToken']['token'] as String;
    if (!unlocked) {
      final key = await execute('{getBibleKey(version:"b1"){key}}');
      final bytes = (await rootBundle.load(
        'assets/bible.bin',
      )).buffer.asUint8List();
      _load(await decrypt(bytes, key['getBibleKey']['key'] as String));
    }
  }

  Future<Uint8List> decrypt(List<int> bytes, String key) async {
    final box = SecretBox(
      bytes.sublist(12, bytes.length - 16),
      nonce: bytes.sublist(0, 12),
      mac: Mac(bytes.sublist(bytes.length - 16)),
    );
    return Uint8List.fromList(
      await _aes.decrypt(box, secretKey: SecretKey(base64Decode(key))),
    );
  }

  void _load(List<int> bytes) {
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    verses = (data['verses'] as List)
        .map((v) => Verse(v as Map<String, dynamic>))
        .toList();
    byId = {for (final v in verses) v.id: v};
    byChapter = {};
    for (final v in verses) {
      byChapter.putIfAbsent('${v.bookCode}.${v.chapter}', () => []).add(v);
    }
  }

  Future<void> download() async {
    if (guestToken.isEmpty) {
      await connect();
    }
    final result = await execute('{downloadBible(version:"b1"){deviceKey}}');
    final key = result['downloadBible']['deviceKey'] as String;
    final payload = utf8.encode(
      jsonEncode({'verses': verses.map((v) => v.json).toList()}),
    );
    final box = await _aes.encrypt(
      payload,
      secretKey: SecretKey(base64Decode(key)),
    );
    final bytes = [...box.nonce, ...box.cipherText, ...box.mac.bytes];
    // Store the key before the ciphertext; a crash can always rebuild the cache.
    await secure.write(key: 'bible_device_key', value: key);
    await store.setSetting('device.bin', base64Encode(bytes));
    offlineReady = true;
  }

  Future<void> clearCache() async {
    await store.removeSetting('device.bin');
    await secure.delete(key: 'bible_device_key');
    offlineReady = false;
  }

  Book book(String alias) => books.firstWhere(
    (b) => b.aliases.any(
      (a) =>
          a.replaceAll(' ', '').toUpperCase() ==
          alias.replaceAll(' ', '').toUpperCase(),
    ),
  );
  Book? tryBook(String alias) {
    try {
      return book(alias);
    } on StateError {
      return null;
    }
  }

  List<Verse> chapter(ChapterPosition position) =>
      byChapter[position.key] ?? [];
  List<Verse> visibleChapter(ChapterPosition position) =>
      chapter(position).where((v) => v.number == v.bridgeStart).toList();
  int chapterSize(ChapterPosition position) =>
      chapterIndex.firstWhere(
            (c) =>
                c['bookCode'] == position.bookCode &&
                c['chapter'] == position.chapter,
          )['verseCount']
          as int;

  List<Verse> resolve(String raw) {
    var query = normalizeQuery(raw);
    if (query.startsWith('logos://verse/')) {
      final parts = query.substring(14).split('.');
      if (parts.length != 3) {
        return [];
      }
      query = '${parts[0]} ${parts[1]}:${parts[2]}';
    }
    final match = RegExp(
      r'^(.+?)\s*(\d{1,3})\s*:\s*(\d{1,3})(?:\s*[-–—]\s*(\d{1,3}))?$',
    ).firstMatch(query);
    if (match == null) {
      return [];
    }
    final b = tryBook(match[1]!.trim());
    if (b == null) {
      return [];
    }
    final c = int.parse(match[2]!);
    final start = int.parse(match[3]!);
    final end = int.parse(match[4] ?? match[3]!);
    if (start < 1 || end < start || end > 176) {
      return [];
    }
    final result = chapter(
      ChapterPosition(b.code, c),
    ).where((v) => v.number >= start && v.number <= end).toList();
    return result.length == end - start + 1 ? result : [];
  }

  List<Verse> search(String raw, {int? testament, String? bookCode}) {
    final query = normalizeQuery(raw);
    if (query.isEmpty) {
      return [];
    }
    final direct = resolve(query);
    final source = direct.isEmpty
        ? verses
              .where(
                (v) =>
                    v.number == v.bridgeStart &&
                    v.text.toLowerCase().contains(query.toLowerCase()),
              )
              .toList()
        : direct;
    return source
        .where(
          (v) =>
              (testament == null || book(v.bookCode).testament == testament) &&
              (bookCode == null || v.bookCode == bookCode),
        )
        .toList();
  }

  String copyText(Verse verse) =>
      '${book(verse.bookCode).abbr}${verse.chapter}:${verse.label}　${verse.text}';

  String formatReferences(Iterable<Verse> selection) {
    final ordered = selection.toList()
      ..sort((a, b) {
        final bookOrder = book(
          a.bookCode,
        ).order.compareTo(book(b.bookCode).order);
        if (bookOrder != 0) return bookOrder;
        final chapterOrder = a.chapter.compareTo(b.chapter);
        return chapterOrder != 0 ? chapterOrder : a.number.compareTo(b.number);
      });
    final chapters = <String, Set<int>>{};
    for (final verse in ordered) {
      final numbers = chapters.putIfAbsent(
        '${book(verse.bookCode).name} ${verse.chapter}',
        () => <int>{},
      );
      final bridge = RegExp(r'^(\d+)-(\d+)$').firstMatch(verse.label);
      final start = bridge == null ? verse.number : int.parse(bridge[1]!);
      final end = bridge == null ? verse.number : int.parse(bridge[2]!);
      for (var number = start; number <= end; number++) {
        numbers.add(number);
      }
    }
    return chapters.entries
        .map((chapter) {
          final numbers = chapter.value.toList()..sort();
          final ranges = <String>[];
          for (var i = 0; i < numbers.length; i++) {
            final start = numbers[i];
            var end = start;
            while (i + 1 < numbers.length && numbers[i + 1] == end + 1) {
              end = numbers[++i];
            }
            ranges.add(start == end ? '$start' : '$start-$end');
          }
          return '${chapter.key}:${ranges.join(',')}';
        })
        .join('; ');
  }

  static const dailyRefs = [
    'JOHN 3:16',
    'PS 23:1',
    'PROV 3:5',
    'PHIL 4:6',
    'ROM 8:28',
    'MATT 6:33',
    'ISA 40:31',
    'PS 119:105',
    'JOHN 15:5',
    'JAS 1:5',
    'PHIL 4:13',
    'PS 46:1',
    'MATT 11:28',
    'ROM 12:2',
    'HEB 11:1',
    '1COR 13:4',
    'PS 1:2',
    'JOHN 14:27',
    'EPH 2:8',
    'JOSH 1:9',
    'PS 121:2',
    'GAL 5:22',
    '1PET 5:7',
    'PS 34:8',
    'ROM 15:13',
    'MATT 5:9',
    'PS 19:14',
    '1JOHN 4:19',
    'HEB 13:8',
    'ISA 41:10',
    'REV 21:4',
  ];
  Verse? get dailyVerse {
    if (!unlocked) {
      return null;
    }
    final today = DateTime.now().toUtc().add(const Duration(hours: 8));
    final ordinal = DateTime.utc(
      2000,
      today.month,
      today.day,
    ).difference(DateTime.utc(2000)).inDays;
    return resolve(dailyRefs[ordinal % dailyRefs.length]).first;
  }
}

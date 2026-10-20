import 'dart:convert';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../data/bible_models.dart';
import '../data/bible_repository.dart';
import '../data/local_store.dart';
import 'account_manager.dart';

final appProvider = ChangeNotifierProvider<AppController>(
  (ref) => AppController(),
);

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({LocalStore? store, AccountManager? accounts})
    : accounts = accounts ?? AccountManager(guest: store ?? LocalStore()) {
    _displayStore = this.accounts.store;
    this.accounts.addListener(_accountChanged);
    this.accounts.onDataChanged = (data) async {
      if (identical(data, this.store)) await _loadPersonal();
    };
    WidgetsBinding.instance.addObserver(this);
    boot();
  }
  final AccountManager accounts;
  LocalStore get store => accounts.store;
  late final bible = BibleRepository(accounts.guest);
  bool _disposed = false;
  LocalStore? _displayStore;
  void _accountChanged() {
    if (accounts.transitioning ||
        accounts.guestLocked ||
        !identical(_displayStore, store)) {
      _displayStore = store;
      bookmarks = [];
      notes = [];
      records = [];
      progress = [];
      searchHistory = [];
      last = const ChapterPosition('GEN', 1);
    }
    if (!_disposed) notifyListeners();
  }

  bool ready = false;
  bool connecting = false;
  String? error;
  String? connectionError;
  bool dark = false;
  double fontSize = 21;
  double lineHeight = 1.85;
  ChapterPosition last = const ChapterPosition('GEN', 1);
  List<Map<String, dynamic>> bookmarks = [];
  List<Map<String, dynamic>> notes = [];
  List<Map<String, dynamic>> records = [];
  List<Map<String, dynamic>> progress = [];
  List<String> searchHistory = [];
  final _uuid = const Uuid();
  bool _sharing = false;

  Future<void> boot() async {
    try {
      await bible.initialize();
      accounts.referenceForId = bible.referenceForId;
      await accounts.restore(bible.server);
      dark = await accounts.guest.setting('dark') == 'true';
      fontSize =
          double.tryParse(await accounts.guest.setting('fontSize') ?? '') ?? 21;
      lineHeight =
          double.tryParse(await accounts.guest.setting('lineHeight') ?? '') ??
          1.85;
      await _loadPersonal();
      if (_disposed) return;
      ready = true;
      notifyListeners();
      accounts.requestSync();
      if (!bible.offlineReady) {
        await reconnect();
      }
    } catch (exception) {
      if (_disposed) return;
      error = accounts.guestLocked ? '个人数据转移尚未完成，数据已保留。' : '初始化失败：$exception';
      ready = true;
      notifyListeners();
    }
  }

  Future<void> reconnect() async {
    if (connecting) {
      return;
    }
    connecting = true;
    connectionError = null;
    notifyListeners();
    try {
      await bible.connect();
    } catch (exception) {
      connectionError = exception.toString().replaceFirst('Bad state: ', '');
    } finally {
      connecting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _loadPersonal() => accounts.withStore((data) async {
    final history =
        (jsonDecode(await data.setting('searchHistory') ?? '[]') as List)
            .cast<String>();
    var position = const ChapterPosition('GEN', 1);
    final saved = await data.setting('lastPosition');
    if (saved != null) {
      final p = jsonDecode(saved) as Map<String, dynamic>;
      position = ChapterPosition(
        p['bookCode'] as String,
        p['chapter'] as int,
        verse: p['verse'] as int,
      );
    }
    if (_disposed || !identical(data, store)) return;
    searchHistory = history;
    last = position;
    await _refreshFrom(data);
  });

  Future<void> _refreshFrom(LocalStore data) async {
    final nextBookmarks = await data.list('bookmark');
    final nextNotes = await data.list('note');
    final nextProgress = await data.list('progress');
    final nextRecords = await data.feed();
    if (_disposed ||
        !identical(data, store) ||
        (accounts.guestLocked && identical(data, accounts.guest))) {
      return;
    }
    bookmarks = nextBookmarks;
    notes = nextNotes;
    progress = nextProgress;
    records = nextRecords;
    notifyListeners();
  }

  Future<void> refresh() => accounts.withStore(_refreshFrom);

  Future<T> _write<T>(Future<T> Function(LocalStore) action) async {
    final result = await accounts.withStore((data) async {
      final value = await action(data);
      if (accounts.account != null) {
        accounts.pendingCount = await data.pendingCount();
      }
      await _refreshFrom(data);
      return value;
    });
    accounts.requestSync();
    return result;
  }

  Future<void> login({
    required String phone,
    required String code,
    required String invite,
  }) async {
    try {
      await accounts.login(
        server: bible.server,
        phone: phone,
        code: code,
        invite: invite,
        deviceId: bible.deviceId,
      );
    } finally {
      if (!_disposed && !accounts.guestLocked) await _loadPersonal();
    }
  }

  Future<void> logout() async {
    await accounts.logout();
    await _loadPersonal();
  }

  Future<void> recoverAccountTransfer() async {
    await accounts.recoverTransfer();
    if (accounts.account == null) await accounts.restore(bible.server);
    await _loadPersonal();
    error = null;
    accounts.requestSync();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) accounts.requestSync();
  }

  Map<String, dynamic>? bookmarkFor(String id) =>
      bookmarks.where((b) => b['verseId'] == id).firstOrNull;
  List<Map<String, dynamic>> notesFor(String id) => notes
      .where((note) => (note['verseIds'] as List? ?? []).contains(id))
      .toList();
  int noteCountFor(String id) => notesFor(id).length;
  Map<String, dynamic> _record(
    String type, {
    Verse? verse,
    String? content,
    String? noteId,
    String? color,
  }) => {
    'id': _uuid.v4(),
    'type': type,
    'verseId': verse?.id,
    'content': content,
    'noteId': noteId,
    'color': color,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  };
  Future<bool> shareVerses(List<Verse> verses) async {
    if (_sharing || verses.isEmpty) return false;
    _sharing = true;
    final sharingStore = store;
    try {
      final selection = List<Verse>.of(verses);
      final first = selection.first;
      final content = selection.map(bible.copyText).join('\n');
      final result = await SharePlus.instance.share(
        ShareParams(
          text:
              '$content\n'
              'logos://verse/${first.bookCode}.${first.chapter}.${first.number}',
        ),
      );
      if (result.status != ShareResultStatus.success ||
          !identical(sharingStore, store) ||
          accounts.transitioning) {
        return false;
      }
      await _write(
        (data) => data.addFeed({
          ..._record('SCRIPTURE_SHARED', verse: first, content: content),
          'verseIds': selection.map((verse) => verse.id).toList(),
        }),
      );
      return true;
    } finally {
      _sharing = false;
    }
  }

  Future<void> bookmark(Verse verse, {String? color, String? note}) =>
      _write((data) async {
        final previous = bookmarkFor(verse.id);
        final now = DateTime.now().toUtc().toIso8601String();
        await data.put(
          'bookmark',
          verse.id,
          {
            'id': verse.id,
            'verseId': verse.id,
            'color': color,
            'note': note,
            'createdAt': previous?['createdAt'] ?? now,
            'updatedAt': now,
          },
          record: _record(
            color == null ? 'BOOKMARK_ADDED' : 'SCRIPTURE_HIGHLIGHT',
            verse: verse,
            content: bible.copyText(verse),
            color: color,
          ),
        );
      });

  Future<void> removeBookmark(String id) => _write((data) async {
    await data.remove('bookmark', id);
  });

  Future<void> clearHighlight(Verse verse) => _write((data) async {
    final previous = bookmarkFor(verse.id);
    if (previous?['color'] == null) return;
    if (noteCountFor(verse.id) == 0) {
      await data.remove('bookmark', verse.id);
      return;
    }
    await data.put('bookmark', verse.id, {
      ...previous!,
      'color': null,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  });

  Future<bool> toggleHighlights(List<Verse> verses, String color) async {
    final remove =
        verses.isNotEmpty &&
        verses.every((verse) => bookmarkFor(verse.id)?['color'] == color);
    for (final verse in verses) {
      if (remove) {
        await clearHighlight(verse);
      } else {
        await bookmark(verse, color: color);
      }
    }
    return remove;
  }

  Future<void> saveNote({
    String? id,
    required String title,
    required String content,
    required List<String> verseIds,
    required List<String> tags,
  }) => _write((data) async {
    final key = id ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final previous = notes.where((n) => n['id'] == key).firstOrNull;
    await data.put(
      'note',
      key,
      {
        'id': key,
        'title': title,
        'content': content,
        'verseIds': verseIds,
        'tags': tags,
        'createdAt': previous?['createdAt'] ?? now,
        'updatedAt': now,
      },
      record: id == null
          ? _record(
              'NOTE_CREATED',
              verse: verseIds.isEmpty ? null : bible.byId[verseIds.first],
              content: content,
              noteId: key,
            )
          : null,
    );
  });

  Future<void> removeNote(String id) => _write((data) async {
    await data.remove('note', id);
  });

  Future<void> recordPosition(ChapterPosition position) async {
    if (accounts.transitioning || accounts.guestLocked) return;
    await _write((data) async {
      last = position;
      await data.setSetting(
        'lastPosition',
        jsonEncode({
          'bookCode': position.bookCode,
          'chapter': position.chapter,
          'verse': position.verse,
        }),
      );
      final previous = progress
          .where((p) => p['id'] == position.key)
          .firstOrNull;
      final currentVerse = previous?['verse'] as int? ?? 1;
      await data.put('progress', position.key, {
        'id': position.key,
        'bookCode': position.bookCode,
        'chapter': position.chapter,
        'verse': position.verse > currentVerse ? position.verse : currentVerse,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<void> addSearch(String query) => _write((data) async {
    if (query.trim().isEmpty) {
      return;
    }
    searchHistory = [
      query,
      ...searchHistory.where((q) => q != query),
    ].take(15).toList();
    await data.setSetting('searchHistory', jsonEncode(searchHistory));
    notifyListeners();
  });

  Future<void> clearSearch() => _write((data) async {
    searchHistory = [];
    await data.setSetting('searchHistory', '[]');
    notifyListeners();
  });

  Future<void> theme(bool value) async {
    dark = value;
    await accounts.guest.setSetting('dark', '$value');
    notifyListeners();
  }

  Future<void> typography(double size, double height) async {
    fontSize = size;
    lineHeight = height;
    notifyListeners();
    await accounts.guest.setSetting('fontSize', '$size');
    await accounts.guest.setSetting('lineHeight', '$height');
  }

  Future<void> setServer(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.path != '/graphql' ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError('请输入以 /graphql 结尾的 HTTP(S) 服务地址');
    }
    if (uri.scheme == 'http' &&
        !['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host)) {
      throw ArgumentError('远程服务请使用 HTTPS');
    }
    if (accounts.account != null ||
        accounts.transitioning ||
        accounts.guestLocked) {
      throw ArgumentError('请先退出账号，再切换服务地址');
    }
    bible.guestToken = '';
    bible.server = value;
    await accounts.guest.setSetting('server', value);
    await reconnect();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    accounts.removeListener(_accountChanged);
    accounts.onDataChanged = null;
    accounts.dispose();
    super.dispose();
  }
}

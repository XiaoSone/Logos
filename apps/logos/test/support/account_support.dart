import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:logos/data/account_remote.dart';
import 'package:logos/data/local_store.dart';
import 'package:logos/state/account_manager.dart';

const testServer = 'http://127.0.0.1:8080/graphql';
const testTime = '2026-10-19T00:00:00.000Z';

class MemoryCredentials implements CredentialStore {
  String? value;
  bool failWrite = false;
  bool failClear = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('安全存储不可用');
    this.value = value;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('安全存储不可用');
    value = null;
  }
}

class FakeAccountRemote implements AccountRemote {
  bool offline = false;
  bool rejectLogin = false;
  bool expired = false;
  bool loseReply = false;
  Set<String> failedKeys = {};
  final List<({String user, List<Map<String, dynamic>> items})> requests = [];
  final Map<String, Map<String, Map<String, dynamic>>> rows = {};
  final Map<String, Set<String>> receipts = {};
  Completer<void>? uploadStarted;
  Completer<void>? uploadGate;
  Completer<void>? fetchStarted;
  Completer<void>? fetchGate;
  Completer<void>? fetched;

  String _scope(AccountCredential c) => '${c.server}:${c.userId}';
  @override
  Future<AccountCredential> login({
    required String server,
    required String phone,
    required String code,
    required String invite,
    required String deviceId,
  }) async {
    if (rejectLogin) throw StateError('测试凭证错误');
    return AccountCredential(
      userId: phone == 'B' ? '2' : '1',
      server: server,
      token: 'test-session-${phone == 'B' ? '2' : '1'}',
      nickname: '读者 $phone',
      phone: '188****000${phone == 'B' ? '2' : '1'}',
    );
  }

  @override
  Future<void> validate(AccountCredential credential) async {
    if (offline) throw StateError('暂时离线');
    if (expired) throw StateError('凭证已过期，请重新连接此账号');
  }

  String _id(String ref) => switch (ref) {
    'JOHN 3:16' => '43003016',
    'JOHN 3:17' => '43003017',
    _ => ref,
  };

  @override
  Future<List<String>> upload(
    AccountCredential credential,
    List<Map<String, dynamic>> items,
  ) async {
    if (offline) throw StateError('暂时离线');
    final scope = _scope(credential);
    final cloud = rows.putIfAbsent(scope, () => {});
    final seen = receipts.putIfAbsent(scope, () => {});
    requests.add((
      user: credential.userId,
      items: (jsonDecode(jsonEncode(items)) as List)
          .cast<Map<String, dynamic>>(),
    ));
    for (final item in items) {
      if (failedKeys.contains(item['clientKey'])) continue;
      if (!seen.add(item['revision'] as String)) continue;
      final ids = ((item['verseRefs'] as List?) ?? [])
          .cast<String>()
          .map(_id)
          .toList();
      final id = item['type'] == 'BOOKMARK'
          ? ids.single
          : item['clientKey'] as String;
      final key = '${item['type']}:$id';
      if (item['operation'] == 'DELETE') {
        cloud.remove(key);
        continue;
      }
      cloud[key] = {
        'id': id,
        'createdAt': item['createdAt'],
        'updatedAt': item['updatedAt'],
        if (item['type'] == 'NOTE') ...{
          'title': item['title'],
          'content': item['content'],
          'verseIds': ids,
          'tags': item['tags'] ?? [],
          'chapterRange': item['chapterRange'],
        },
        if (item['type'] == 'BOOKMARK') ...{
          'verseId': id,
          'color': item['color'],
          'note': item['note'],
        },
        if (item['type'] == 'PROGRESS') ...{
          'bookCode': item['bookCode'],
          'chapter': item['chapter'],
          'verse': item['verse'],
        },
        if (item['type'] == 'FEED_RECORD') ...{
          'type': 'SCRIPTURE_SHARED',
          'verseIds': ids,
          'content': item['content'],
        },
      };
    }
    if (uploadStarted?.isCompleted == false) uploadStarted!.complete();
    await uploadGate?.future;
    if (loseReply) {
      loseReply = false;
      throw StateError('响应丢失');
    }
    return items
        .map((i) => i['clientKey'] as String)
        .where(failedKeys.contains)
        .toList();
  }

  @override
  Future<StoreSnapshot> fetch(AccountCredential credential) async {
    if (offline) throw StateError('暂时离线');
    final cloud = rows.putIfAbsent(_scope(credential), () => {});
    // Snapshot the response before waiting, to model edits arriving while a pull is in flight.
    final saved = (jsonDecode(jsonEncode(cloud)) as Map)
        .cast<String, dynamic>();
    if (fetchStarted?.isCompleted == false) fetchStarted!.complete();
    await fetchGate?.future;
    final snapshot = StoreSnapshot(
      {
        for (final pair in [
          ('bookmark', 'BOOKMARK'),
          ('note', 'NOTE'),
          ('progress', 'PROGRESS'),
        ])
          pair.$1: [
            for (final entry in saved.entries)
              if (entry.key.startsWith('${pair.$2}:'))
                entry.value as Map<String, dynamic>,
          ],
      },
      [
        for (final entry in saved.entries)
          if (entry.key.startsWith('FEED_RECORD:'))
            entry.value as Map<String, dynamic>,
      ],
      [],
      {},
    );
    if (fetched?.isCompleted == false) fetched!.complete();
    return snapshot;
  }
}

class AccountTestRig {
  AccountTestRig(this.directory, this.credentials, this.remote);
  final Directory directory;
  final MemoryCredentials credentials;
  final FakeAccountRemote remote;
  LocalStore open(String name) {
    final executor = NativeDatabase(File('${directory.path}/$name.db'));
    return name == 'guest'
        ? LocalStore(executor)
        : LocalStore.named(name, executor: executor);
  }

  AccountManager manager({
    LocalStore? guest,
    LocalStore Function(String)? factory,
    Duration retry = const Duration(days: 1),
    Duration debounce = const Duration(days: 1),
  }) =>
      AccountManager(
          guest: guest ?? open('guest'),
          credentials: credentials,
          remote: remote,
          openStore: factory ?? open,
          retryDelay: retry,
          debounceDelay: debounce,
        )
        ..referenceForId = (id) => switch (id) {
          '43003016' => 'JOHN 3:16',
          '43003017' => 'JOHN 3:17',
          _ => id,
        };
}

Future<void> connectTestAccount(
  AccountManager manager, {
  String phone = 'A',
  String server = testServer,
}) => manager.login(
  server: server,
  phone: phone,
  code: 'test',
  invite: 'test',
  deviceId: 'test-device',
);

Future<void> addTestNote(
  LocalStore store,
  String id, {
  String content = '个人笔记',
  String updated = testTime,
}) => store.put('note', id, {
  'id': id,
  'title': '标题',
  'content': content,
  'verseIds': ['43003016', '43003017'],
  'tags': ['带,逗号'],
  'createdAt': testTime,
  'updatedAt': updated,
});

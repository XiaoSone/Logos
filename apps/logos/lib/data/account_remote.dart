import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'local_store.dart';

class AccountCredential {
  const AccountCredential({
    required this.userId,
    required this.server,
    required this.token,
    required this.nickname,
    required this.phone,
  });
  final String userId;
  final String server;
  final String token;
  final String nickname;
  final String phone;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'server': server,
    'token': token,
    'nickname': nickname,
    'phone': phone,
  };
  factory AccountCredential.fromJson(Map<String, dynamic> json) {
    final result = AccountCredential(
      userId: json['userId'] as String,
      server: json['server'] as String,
      token: json['token'] as String,
      nickname: json['nickname'] as String,
      phone: json['phone'] as String,
    );
    if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(result.userId) ||
        result.token.isEmpty) {
      throw const FormatException('无效账号信息');
    }
    canonicalServer(result.server);
    return result;
  }
}

String canonicalServer(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.path != '/graphql' ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty ||
      (uri.scheme == 'http' &&
          !['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host))) {
    throw ArgumentError('请输入有效的 /graphql 服务地址；远程服务请使用 HTTPS');
  }
  return uri.toString();
}

Future<String> accountDatabaseName(String server, String userId) async {
  if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(userId)) {
    throw ArgumentError('无效账号编号');
  }
  final hash = await Sha256().hash(utf8.encode(canonicalServer(server)));
  final scope = hash.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'user_${scope}_$userId';
}

abstract interface class CredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureCredentialStore implements CredentialStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'logos_account_session_v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

abstract class AccountRemote {
  Future<AccountCredential> login({
    required String server,
    required String phone,
    required String code,
    required String invite,
    required String deviceId,
  });
  Future<void> validate(AccountCredential credential);
  Future<List<String>> upload(
    AccountCredential credential,
    List<Map<String, dynamic>> items,
  );
  Future<StoreSnapshot> fetch(AccountCredential credential);
}

class GraphQlAccountRemote implements AccountRemote {
  Future<Map<String, dynamic>> _send(
    String server,
    String? token,
    String document, {
    Map<String, dynamic> variables = const {},
    bool mutation = false,
  }) async {
    final link = HttpLink(
      canonicalServer(server),
      defaultHeaders: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    final client = GraphQLClient(
      link: link,
      cache: GraphQLCache(store: InMemoryStore()),
    );
    try {
      final result =
          await (mutation
                  ? client.mutate(
                      MutationOptions(
                        document: gql(document),
                        variables: variables,
                        fetchPolicy: FetchPolicy.noCache,
                      ),
                    )
                  : client.query(
                      QueryOptions(
                        document: gql(document),
                        variables: variables,
                        fetchPolicy: FetchPolicy.noCache,
                      ),
                    ))
              .timeout(const Duration(seconds: 15));
      if (result.hasException) {
        final errors = result.exception!.graphqlErrors;
        throw StateError(
          errors.isEmpty ? '暂时无法连接账号服务，本地数据已保留。' : errors.first.message,
        );
      }
      return result.data!;
    } finally {
      await link.dispose();
    }
  }

  @override
  Future<AccountCredential> login({
    required String server,
    required String phone,
    required String code,
    required String invite,
    required String deviceId,
  }) async {
    final available = await _send(server, null, '{loginAvailable}');
    if (available['loginAvailable'] != true) {
      throw StateError('正式短信通道尚未配置，请使用游客模式。');
    }
    final result = await _send(
      server,
      null,
      r'mutation($phone:String!,$code:String!,$invite:String!,$device:String!){verifySmsCode(phone:$phone,code:$code,inviteCode:$invite,deviceId:$device){accessToken user{id nickname phone}}}',
      variables: {
        'phone': phone,
        'code': code,
        'invite': invite,
        'device': deviceId,
      },
      mutation: true,
    );
    final auth = result['verifySmsCode'] as Map<String, dynamic>;
    final user = auth['user'] as Map<String, dynamic>;
    return AccountCredential.fromJson({
      'userId': user['id'],
      'server': canonicalServer(server),
      'token': auth['accessToken'],
      'nickname': user['nickname'] ?? 'Logos 读者',
      'phone': user['phone'] ?? '',
    });
  }

  @override
  Future<void> validate(AccountCredential credential) async {
    final result = await _send(credential.server, credential.token, '{me{id}}');
    if ((result['me'] as Map?)?['id'] != credential.userId) {
      throw StateError('账号凭证不匹配，请重新连接此账号。');
    }
  }

  @override
  Future<List<String>> upload(
    AccountCredential credential,
    List<Map<String, dynamic>> items,
  ) async {
    final result = await _send(
      credential.server,
      credential.token,
      r'mutation($items:[GuestDataItem!]!){importGuestData(items:$items){imported failed}}',
      variables: {'items': items},
      mutation: true,
    );
    return ((result['importGuestData'] as Map)['failed'] as List)
        .cast<String>();
  }

  String _utc(dynamic value) =>
      DateTime.parse(value as String).toUtc().toIso8601String();

  @override
  Future<StoreSnapshot> fetch(AccountCredential credential) async {
    final result = await _send(credential.server, credential.token, '''
      {mySyncSnapshot{userId
        bookmarks{verse{id} color note createdAt updatedAt}
        notes{clientKey title content tags chapterRange verses{id} createdAt updatedAt}
        progress{book{bookCode} chapter verse readAt}
        shares{id clientKey type verseIds content createdAt}
      }}
    ''');
    final snapshot = result['mySyncSnapshot'] as Map<String, dynamic>;
    if (snapshot['userId'] != credential.userId) throw StateError('账号快照归属不匹配');
    return StoreSnapshot(
      {
        'bookmark': [
          for (final row in snapshot['bookmarks'] as List)
            {
              'id': row['verse']['id'],
              'verseId': row['verse']['id'],
              'color': row['color'],
              'note': row['note'],
              'createdAt': _utc(row['createdAt']),
              'updatedAt': _utc(row['updatedAt']),
            },
        ],
        'note': [
          for (final row in snapshot['notes'] as List)
            {
              'id': row['clientKey'],
              'title': row['title'],
              'content': row['content'],
              'tags': row['tags'],
              'chapterRange': row['chapterRange'],
              'verseIds': [
                for (final verse in row['verses'] as List) verse['id'],
              ],
              'createdAt': _utc(row['createdAt']),
              'updatedAt': _utc(row['updatedAt']),
            },
        ],
        'progress': [
          for (final row in snapshot['progress'] as List)
            {
              'id': '${row['book']['bookCode']}.${row['chapter']}',
              'bookCode': row['book']['bookCode'],
              'chapter': row['chapter'],
              'verse': row['verse'],
              'updatedAt': _utc(row['readAt']),
            },
        ],
      },
      [
        for (final row in snapshot['shares'] as List)
          {
            'id': row['clientKey'] ?? 'cloud-share-${row['id']}',
            'type': 'SCRIPTURE_SHARED',
            'verseIds': row['verseIds'],
            'content': row['content'],
            'createdAt': _utc(row['createdAt']),
          },
      ],
      const [],
      const {},
    );
  }
}

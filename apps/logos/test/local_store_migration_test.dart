import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logos/data/local_store.dart';

// The actual v1 schema, kept independent from the implementation under test.
class LegacyStore extends GeneratedDatabase {
  LegacyStore(File file) : super(NativeDatabase(file));
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE user_data (kind TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(kind,id))',
      );
      await customStatement(
        'CREATE TABLE feed_record (id TEXT PRIMARY KEY, type TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE INDEX feed_cursor ON feed_record(created_at DESC,id DESC)',
      );
      await customStatement(
        'CREATE TABLE sync_queue (kind TEXT NOT NULL, client_key TEXT NOT NULL, PRIMARY KEY(kind,client_key))',
      );
      await customStatement(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const time = '2026-10-17T00:00:00.000Z';
  const note = {
    'id': 'note-1',
    'title': '保留标题',
    'content': '保留正文',
    'verseIds': ['43003016', '43003017'],
    'tags': ['带,逗号', '引"号', '灵修'],
    'createdAt': time,
    'updatedAt': time,
  };
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('logos-migration-');
    file = File('${directory.path}/guest.db');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<void> seed(
    LegacyStore legacy,
    String kind,
    String id,
    Map<String, dynamic> value,
  ) => legacy.customStatement('INSERT INTO user_data VALUES(?,?,?,?)', [
    kind,
    id,
    jsonEncode(value),
    time,
  ]);

  test(
    'v1 upgrades on disk with notes, marks, progress, shares and settings intact',
    () async {
      final legacy = LegacyStore(file);
      await seed(legacy, 'note', 'note-1', note);
      await seed(legacy, 'bookmark', '43003016', {
        'id': '43003016',
        'verseId': '43003016',
        'color': '#F2D893',
        'note': '备注',
        'createdAt': time,
        'updatedAt': time,
      });
      await seed(legacy, 'progress', 'JOHN.3', {
        'id': 'JOHN.3',
        'bookCode': 'JOHN',
        'chapter': 3,
        'verse': 16,
        'updatedAt': time,
      });
      for (final record in [
        {
          'id': 'highlight',
          'type': 'SCRIPTURE_HIGHLIGHT',
          'verseId': '43003016',
          'color': '#F2D893',
          'createdAt': time,
        },
        {
          'id': 'note-event',
          'type': 'NOTE_CREATED',
          'noteId': 'note-1',
          'createdAt': time,
        },
        {
          'id': 'share',
          'type': 'SCRIPTURE_SHARED',
          'verseIds': ['43003016', '43003017'],
          'content': '完整分享',
          'createdAt': time,
        },
      ]) {
        await legacy.customStatement(
          'INSERT INTO feed_record VALUES(?,?,?,?)',
          [record['id'], record['type'], jsonEncode(record), time],
        );
      }
      await legacy.customStatement(
        "INSERT INTO settings VALUES('lastPosition','retained')",
      );
      await legacy.customStatement(
        "INSERT INTO settings VALUES('device.bin','encrypted-cache')",
      );
      await legacy.customStatement(
        "INSERT INTO sync_queue VALUES('note','note-1')",
      );
      await legacy.close();

      final store = LocalStore(NativeDatabase(file));
      expect(
        (await store.list('note')).single,
        containsPair('tags', note['tags']),
      );
      expect((await store.list('note')).single['content'], note['content']);
      expect((await store.list('bookmark')).single['note'], '备注');
      expect((await store.list('progress')).single['verse'], 16);
      expect(await store.feed(), hasLength(3));
      expect(
        (await store.feed()).singleWhere((e) => e['id'] == 'share')['verseIds'],
        ['43003016', '43003017'],
      );
      expect(await store.setting('lastPosition'), 'retained');
      expect(await store.setting('device.bin'), 'encrypted-cache');
      expect(await store.pendingChanges(), hasLength(4));
      expect(
        await store
            .customSelect(
              "SELECT name FROM sqlite_master WHERE name IN ('user_data','sync_queue_v1')",
            )
            .get(),
        isEmpty,
      );
      await store.close();

      final reopened = LocalStore(NativeDatabase(file));
      expect(await reopened.pendingChanges(), hasLength(4));
      expect(await reopened.feed(), hasLength(3));
      await reopened.close();
    },
  );

  test(
    'an unsupported legacy row aborts the whole upgrade without losing v1 data',
    () async {
      final legacy = LegacyStore(file);
      await seed(legacy, 'note', 'note-1', note);
      await seed(legacy, 'unknown-kind', 'preserve-me', {'id': 'preserve-me'});
      await legacy.close();
      final store = LocalStore(NativeDatabase(file));
      await expectLater(store.list('note'), throwsArgumentError);
      await store.close();
      final old = LegacyStore(file);
      expect(
        await old.customSelect('SELECT id FROM user_data').get(),
        hasLength(2),
      );
      expect(
        await old
            .customSelect("SELECT name FROM sqlite_master WHERE name='notes'")
            .get(),
        isEmpty,
      );
      await old.close();
    },
  );

  test(
    'delete survives restart; acknowledging an earlier upload cannot drop a tombstone or new edit',
    () async {
      var store = LocalStore(NativeDatabase(file));
      await store.put('note', 'note-1', note);
      final original = await store.pendingChanges();
      await store.remove('note', 'note-1');
      await store.acknowledgeChanges(original);
      expect(await store.list('note'), isEmpty);
      final deletion = (await store.pendingChanges()).single;
      expect(deletion.operation, 'DELETE');
      expect(deletion.value['verseIds'], note['verseIds']);
      await store.close();
      store = LocalStore(NativeDatabase(file));
      expect((await store.pendingChanges()).single.revision, deletion.revision);
      await store.put('note', 'note-1', {...note, 'content': '恢复后重新编辑'});
      await store.acknowledgeChanges([deletion]);
      final updated = (await store.pendingChanges()).single;
      expect(updated.operation, 'UPSERT');
      expect(updated.value['content'], '恢复后重新编辑');
      await store.acknowledgeChanges([updated]);
      expect(await store.pendingChanges(), isEmpty);
      expect(await store.list('note'), hasLength(1));
      await store.close();
    },
  );

  test(
    'failed mutation rolls back entity, queue revision and feed together',
    () async {
      final store = LocalStore(NativeDatabase.memory());
      await store.put('note', 'note-1', note);
      final revision = (await store.pendingChanges()).single.revision;
      await store.customStatement('''
      CREATE TRIGGER reject_feed BEFORE INSERT ON feed_record
      BEGIN SELECT RAISE(ABORT, 'test failure'); END
    ''');
      await expectLater(
        store.put(
          'note',
          'note-1',
          {...note, 'content': '不应写入'},
          record: {'id': 'fail', 'type': 'NOTE_CREATED', 'createdAt': time},
        ),
        throwsException,
      );
      expect((await store.list('note')).single['content'], note['content']);
      expect((await store.pendingChanges()).single.revision, revision);
      expect(await store.feed(), isEmpty);
      await store.close();
    },
  );

  test(
    'queued progress uses the stored maximum and only shares enqueue explicit feed',
    () async {
      final store = LocalStore(NativeDatabase.memory());
      for (final verse in [16, 2]) {
        await store.put('progress', 'JOHN.3', {
          'bookCode': 'JOHN',
          'chapter': 3,
          'verse': verse,
          'updatedAt': time,
        });
      }
      expect((await store.pendingChanges()).single.value['verse'], 16);
      for (final type in [
        'NOTE_CREATED',
        'BOOKMARK_ADDED',
        'SCRIPTURE_SHARED',
      ]) {
        await store.addFeed({'id': type, 'type': type, 'createdAt': time});
      }
      expect(
        (await store.pendingChanges()).map((c) => c.clientKey),
        unorderedEquals(['JOHN.3', 'SCRIPTURE_SHARED']),
      );
      await store.close();
    },
  );
}

import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'connection.dart';

/// A durable snapshot. Acknowledging an old snapshot cannot erase a newer edit.
class PendingChange {
  const PendingChange(
    this.kind,
    this.clientKey,
    this.operation,
    this.revision,
    this.value,
  );
  final String kind;
  final String clientKey;
  final String operation;
  final String revision;
  final Map<String, dynamic> value;
}

class StoreSnapshot {
  const StoreSnapshot(this.data, this.records, this.pending, this.settings);
  final Map<String, List<Map<String, dynamic>>> data;
  final List<Map<String, dynamic>> records;
  final List<PendingChange> pending;
  final Map<String, String> settings;
}

/// Drift owns all guest data. Mutations and their feed entries commit together.
class LocalStore extends GeneratedDatabase {
  LocalStore([QueryExecutor? executor]) : super(executor ?? openConnection());
  factory LocalStore.named(String name, {QueryExecutor? executor}) =>
      _AccountLocalStore(executor ?? openConnection(name: name));
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await _createPersonalTables();
      await customStatement(
        'CREATE TABLE feed_record (id TEXT PRIMARY KEY, type TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE INDEX feed_cursor ON feed_record(created_at DESC,id DESC)',
      );
      await _createQueue();
      await customStatement(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    },
    onUpgrade: (_, from, to) => transaction(() async {
      if (from != 1 || to != 2) {
        throw StateError('不支持的本地数据库版本');
      }
      await _createPersonalTables();
      // v1 has never uploaded guest data. Rebuild its queue from all live rows.
      await customStatement('ALTER TABLE sync_queue RENAME TO sync_queue_v1');
      await _createQueue();
      final highlights = await customSelect(
        "SELECT body FROM feed_record WHERE type='SCRIPTURE_HIGHLIGHT'",
      ).get();
      final rows = await customSelect(
        'SELECT kind,id,body FROM user_data',
      ).get();
      for (final row in rows) {
        await put(
          row.read<String>('kind'),
          row.read<String>('id'),
          jsonDecode(row.read<String>('body')) as Map<String, dynamic>,
        );
      }
      // put() replaces highlight history during normal edits, not during upgrade.
      for (final row in highlights) {
        await addFeed(
          jsonDecode(row.read<String>('body')) as Map<String, dynamic>,
        );
      }
      final shares = await customSelect(
        "SELECT id,body FROM feed_record WHERE type='SCRIPTURE_SHARED'",
      ).get();
      for (final row in shares) {
        await _enqueue(
          'feed',
          row.read<String>('id'),
          'UPSERT',
          jsonDecode(row.read<String>('body')) as Map<String, dynamic>,
        );
      }
      await customStatement('DROP TABLE user_data');
      await customStatement('DROP TABLE sync_queue_v1');
    }),
  );

  Future<void> _createPersonalTables() async {
    await customStatement('''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY, verse_id TEXT NOT NULL UNIQUE, color TEXT, note TEXT,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
    ''');
    await customStatement('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY, title TEXT, content TEXT NOT NULL,
        verse_ids TEXT NOT NULL CHECK(json_valid(verse_ids)),
        tags TEXT NOT NULL CHECK(json_valid(tags)), chapter_range TEXT,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
    ''');
    await customStatement('''
      CREATE TABLE reading_progress (
        id TEXT PRIMARY KEY, book_code TEXT NOT NULL, chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL, updated_at TEXT NOT NULL,
        UNIQUE(book_code,chapter))
    ''');
  }

  Future<void> _createQueue() => customStatement('''
    CREATE TABLE sync_queue (
      kind TEXT NOT NULL, client_key TEXT NOT NULL,
      operation TEXT NOT NULL CHECK(operation IN ('UPSERT','DELETE')),
      revision TEXT NOT NULL, body TEXT NOT NULL, queued_at TEXT NOT NULL,
      PRIMARY KEY(kind,client_key))
  ''');

  String _table(String kind) => switch (kind) {
    'bookmark' => 'bookmarks',
    'note' => 'notes',
    'progress' => 'reading_progress',
    _ => throw ArgumentError.value(kind, 'kind'),
  };

  Future<void> _enqueue(
    String kind,
    String id,
    String operation,
    Map<String, dynamic> value,
  ) => customStatement(
    '''
    INSERT INTO sync_queue(kind,client_key,operation,revision,body,queued_at)
    VALUES(?,?,?,?,?,?) ON CONFLICT(kind,client_key) DO UPDATE SET
    operation=excluded.operation,revision=excluded.revision,
    body=excluded.body,queued_at=excluded.queued_at
  ''',
    [
      kind,
      id,
      operation,
      const Uuid().v4(),
      jsonEncode(value),
      DateTime.now().toUtc().toIso8601String(),
    ],
  );

  Future<List<PendingChange>> pendingChanges({
    int limit = 100,
    Set<String> excluding = const {},
  }) async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
    final rows = await customSelect(
      'SELECT kind,client_key,operation,revision,body FROM sync_queue '
      '${excluding.isEmpty ? '' : 'WHERE revision NOT IN (${List.filled(excluding.length, '?').join(',')}) '}'
      'ORDER BY queued_at,kind,client_key LIMIT ?',
      variables: [...excluding.map(Variable.new), Variable(limit)],
    ).get();
    return rows
        .map(
          (row) => PendingChange(
            row.read<String>('kind'),
            row.read<String>('client_key'),
            row.read<String>('operation'),
            row.read<String>('revision'),
            jsonDecode(row.read<String>('body')) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<int> pendingCount() async => (await customSelect(
    'SELECT COUNT(*) AS count FROM sync_queue',
  ).getSingle()).read<int>('count');

  Future<List<PendingChange>> _allPending() async =>
      (await customSelect(
            'SELECT kind,client_key,operation,revision,body FROM sync_queue',
          ).get())
          .map(
            (row) => PendingChange(
              row.read<String>('kind'),
              row.read<String>('client_key'),
              row.read<String>('operation'),
              row.read<String>('revision'),
              jsonDecode(row.read<String>('body')) as Map<String, dynamic>,
            ),
          )
          .toList();

  Future<StoreSnapshot> snapshot() => transaction(() async {
    final settings = <String, String>{};
    for (final key in ['lastPosition', 'searchHistory']) {
      final value = await setting(key);
      if (value != null) settings[key] = value;
    }
    return StoreSnapshot(
      {
        for (final kind in ['bookmark', 'note', 'progress'])
          kind: await list(kind),
      },
      await feed(),
      await _allPending(),
      settings,
    );
  });

  Future<void> _restoreChange(PendingChange change) => customStatement(
    '''
    INSERT INTO sync_queue(kind,client_key,operation,revision,body,queued_at)
    VALUES(?,?,?,?,?,?) ON CONFLICT(kind,client_key) DO UPDATE SET
    operation=excluded.operation,revision=excluded.revision,body=excluded.body,
    queued_at=excluded.queued_at
  ''',
    [
      change.kind,
      change.clientKey,
      change.operation,
      change.revision,
      jsonEncode(change.value),
      DateTime.now().toUtc().toIso8601String(),
    ],
  );

  DateTime _time(Map<String, dynamic> value) => DateTime.parse(
    (value['updatedAt'] ?? value['createdAt']) as String,
  ).toUtc();

  /// Idempotent destination commit. The source is cleared only after this returns.
  Future<void> adoptGuest(StoreSnapshot source, String transferId) =>
      transaction(() async {
        if (await setting('lastGuestTransfer') == transferId) return;
        final pending = {
          for (final c in await _allPending()) '${c.kind}:${c.clientKey}': c,
        };
        final incoming = {
          for (final c in source.pending) '${c.kind}:${c.clientKey}': c,
        };
        for (final kind in ['bookmark', 'note', 'progress']) {
          final existing = {
            for (final row in await list(kind)) row['id'] as String: row,
          };
          for (final value in source.data[kind] ?? <Map<String, dynamic>>[]) {
            final id = value['id'] as String;
            final current = existing[id];
            final queued = pending['$kind:$id'];
            var merged = value;
            if (kind == 'progress' && current != null) {
              merged = {
                ...value,
                'verse': (current['verse'] as int) > (value['verse'] as int)
                    ? current['verse']
                    : value['verse'],
                'updatedAt': _time(current).isAfter(_time(value))
                    ? current['updatedAt']
                    : value['updatedAt'],
              };
            } else if (current != null || queued != null) {
              final latest = queued?.value ?? current!;
              if (!_time(value).isAfter(_time(latest))) continue;
            }
            await _saveEntity(kind, id, merged);
            final change = incoming['$kind:$id'];
            if (change != null && jsonEncode(merged) == jsonEncode(value)) {
              await _restoreChange(change);
            } else {
              await _enqueue(kind, id, 'UPSERT', merged);
            }
          }
          for (final change in source.pending.where(
            (c) => c.kind == kind && c.operation == 'DELETE',
          )) {
            final latest =
                pending['$kind:${change.clientKey}']?.value ??
                existing[change.clientKey];
            if (latest != null && _time(latest).isAfter(_time(change.value))) {
              continue;
            }
            await customStatement('DELETE FROM ${_table(kind)} WHERE id=?', [
              change.clientKey,
            ]);
            if (kind == 'bookmark') {
              await _removeHighlightRecords(change.clientKey);
            }
            await _restoreChange(change);
          }
        }
        final recordIds = (await customSelect(
          'SELECT id FROM feed_record',
        ).get()).map((row) => row.read<String>('id')).toSet();
        for (final record in source.records) {
          if (!recordIds.add(record['id'] as String)) continue;
          await _cacheFeed(record);
          final change = incoming['feed:${record['id']}'];
          if (change != null) {
            await _restoreChange(change);
          } else if (record['type'] == 'SCRIPTURE_SHARED') {
            await _enqueue('feed', record['id'] as String, 'UPSERT', record);
          }
        }
        for (final entry in source.settings.entries) {
          if (entry.key == 'searchHistory') {
            final combined = <String>{
              ...(jsonDecode(entry.value) as List).cast<String>(),
              ...(jsonDecode(await setting('searchHistory') ?? '[]') as List)
                  .cast<String>(),
            };
            await setSetting(entry.key, jsonEncode(combined.take(15).toList()));
          } else {
            await setSetting(entry.key, entry.value);
          }
        }
        await setSetting('lastGuestTransfer', transferId);
      });

  Future<void> clearGuestBusiness() => transaction(() async {
    for (final table in [
      'bookmarks',
      'notes',
      'reading_progress',
      'feed_record',
      'sync_queue',
    ]) {
      await customStatement('DELETE FROM $table');
    }
    await customStatement(
      "DELETE FROM settings WHERE key IN ('lastPosition','searchHistory','guestTransfer')",
    );
  });

  Future<void> _cacheFeed(Map<String, dynamic> record) => customStatement(
    'INSERT OR IGNORE INTO feed_record(id,type,body,created_at) VALUES(?,?,?,?)',
    [record['id'], record['type'], jsonEncode(record), record['createdAt']],
  );

  /// A full authoritative cache plus unacknowledged local edits, committed together.
  Future<void> replaceSynced(StoreSnapshot cloud) => transaction(() async {
    final pending = await _allPending();
    for (final kind in ['bookmark', 'note', 'progress']) {
      await customStatement('DELETE FROM ${_table(kind)}');
      for (final value in cloud.data[kind] ?? <Map<String, dynamic>>[]) {
        await _saveEntity(kind, value['id'] as String, value);
      }
    }
    await customStatement(
      "DELETE FROM feed_record WHERE type='SCRIPTURE_SHARED'",
    );
    for (final record in cloud.records) {
      await _cacheFeed(record);
    }
    for (final change in pending) {
      if (change.kind == 'feed') {
        await _cacheFeed(change.value);
      } else if (change.operation == 'DELETE') {
        await customStatement('DELETE FROM ${_table(change.kind)} WHERE id=?', [
          change.clientKey,
        ]);
        if (change.kind == 'bookmark') {
          await _removeHighlightRecords(change.clientKey);
        }
      } else {
        await _saveEntity(change.kind, change.clientKey, change.value);
      }
    }
    if (await setting('lastPosition') == null) {
      final positions = await list('progress');
      if (positions.isNotEmpty) {
        final latest = positions.first;
        await setSetting(
          'lastPosition',
          jsonEncode({
            'bookCode': latest['bookCode'],
            'chapter': latest['chapter'],
            'verse': latest['verse'],
          }),
        );
      }
    }
  });

  Future<void> acknowledgeChanges(List<PendingChange> changes) => transaction(
    () async {
      for (final change in changes) {
        await customStatement(
          'DELETE FROM sync_queue WHERE kind=? AND client_key=? AND revision=?',
          [change.kind, change.clientKey, change.revision],
        );
      }
    },
  );

  Future<String?> setting(String key) async {
    final row = await customSelect(
      'SELECT value FROM settings WHERE key=?',
      variables: [Variable(key)],
    ).getSingleOrNull();
    return row?.read<String>('value');
  }

  Future<void> setSetting(String key, String value) => customStatement(
    'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  Future<void> removeSetting(String key) =>
      customStatement('DELETE FROM settings WHERE key=?', [key]);
  Future<List<Map<String, dynamic>>> list(String kind) async {
    final rows = await customSelect(
      'SELECT * FROM ${_table(kind)} ORDER BY updated_at DESC,id DESC',
    ).get();
    return rows.map((row) => _value(kind, row)).toList();
  }

  Map<String, dynamic> _value(String kind, QueryRow row) => {
    'id': row.read<String>('id'),
    'updatedAt': row.read<String>('updated_at'),
    if (kind != 'progress') 'createdAt': row.read<String>('created_at'),
    if (kind == 'bookmark') ...{
      'verseId': row.read<String>('verse_id'),
      'color': row.readNullable<String>('color'),
      'note': row.readNullable<String>('note'),
    },
    if (kind == 'note') ...{
      'title': row.readNullable<String>('title'),
      'content': row.read<String>('content'),
      'verseIds': jsonDecode(row.read<String>('verse_ids')),
      'tags': jsonDecode(row.read<String>('tags')),
      'chapterRange': row.readNullable<String>('chapter_range'),
    },
    if (kind == 'progress') ...{
      'bookCode': row.read<String>('book_code'),
      'chapter': row.read<int>('chapter'),
      'verse': row.read<int>('verse'),
    },
  };

  Future<List<Map<String, dynamic>>> feed() => transaction(() async {
    await customStatement(
      "DELETE FROM feed_record WHERE type='VERSE_SELECTED'",
    );
    final rows = await customSelect(
      'SELECT id,body FROM feed_record ORDER BY created_at DESC,id DESC',
    ).get();
    final activeColors = {
      for (final bookmark in await list('bookmark'))
        if (bookmark['color'] != null) bookmark['verseId']: bookmark['color'],
    };
    final visibleHighlights = <String>{};
    final records = <Map<String, dynamic>>[];
    for (final row in rows) {
      final record =
          jsonDecode(row.read<String>('body')) as Map<String, dynamic>;
      if (record['type'] == 'SCRIPTURE_HIGHLIGHT') {
        final verseId = record['verseId'] as String?;
        // Remove stale and duplicate marks left by older app versions as well.
        if (verseId == null ||
            !activeColors.containsKey(verseId) ||
            activeColors[verseId] != record['color'] ||
            !visibleHighlights.add(verseId)) {
          await customStatement('DELETE FROM feed_record WHERE id=?', [
            row.read<String>('id'),
          ]);
          continue;
        }
      }
      records.add(record);
    }
    return records;
  });

  Future<void> _removeHighlightRecords(String verseId) => customStatement(
    r"DELETE FROM feed_record WHERE type='SCRIPTURE_HIGHLIGHT' AND json_extract(body, '$.verseId')=?",
    [verseId],
  );

  Future<void> put(
    String kind,
    String id,
    Map<String, dynamic> value, {
    Map<String, dynamic>? record,
  }) => transaction(() async {
    await _saveEntity(kind, id, value);
    final saved = await customSelect(
      'SELECT * FROM ${_table(kind)} WHERE id=?',
      variables: [Variable(id)],
    ).getSingle();
    await _enqueue(kind, id, 'UPSERT', _value(kind, saved));
    if (kind == 'bookmark') await _removeHighlightRecords(id);
    if (record != null) {
      await addFeed(record);
    }
  });
  Future<void> _saveEntity(
    String kind,
    String id,
    Map<String, dynamic> value,
  ) async {
    final updated =
        value['updatedAt'] ?? DateTime.now().toUtc().toIso8601String();
    final created = value['createdAt'] ?? updated;
    switch (kind) {
      case 'bookmark':
        await customStatement(
          '''
          INSERT INTO bookmarks(id,verse_id,color,note,created_at,updated_at)
          VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
          color=excluded.color,note=excluded.note,updated_at=excluded.updated_at
        ''',
          [
            id,
            value['verseId'] ?? id,
            value['color'],
            value['note'],
            created,
            updated,
          ],
        );
      case 'note':
        await customStatement(
          '''
          INSERT INTO notes(id,title,content,verse_ids,tags,chapter_range,created_at,updated_at)
          VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
          title=excluded.title,content=excluded.content,verse_ids=excluded.verse_ids,
          tags=excluded.tags,chapter_range=excluded.chapter_range,updated_at=excluded.updated_at
        ''',
          [
            id,
            value['title'],
            value['content'],
            jsonEncode(value['verseIds'] ?? []),
            jsonEncode(value['tags'] ?? []),
            value['chapterRange'],
            created,
            updated,
          ],
        );
      case 'progress':
        await customStatement(
          '''
          INSERT INTO reading_progress(id,book_code,chapter,verse,updated_at)
          VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
          verse=MAX(reading_progress.verse,excluded.verse),updated_at=excluded.updated_at
        ''',
          [id, value['bookCode'], value['chapter'], value['verse'], updated],
        );
      default:
        throw ArgumentError.value(kind, 'kind');
    }
  }

  Future<void> addFeed(Map<String, dynamic> record) => transaction(() async {
    await customStatement(
      'INSERT OR IGNORE INTO feed_record(id,type,body,created_at) VALUES(?,?,?,?)',
      [record['id'], record['type'], jsonEncode(record), record['createdAt']],
    );
    // Bookmark/note events are generated by the server on import, avoiding doubles.
    if (record['type'] == 'SCRIPTURE_SHARED') {
      final saved = await customSelect(
        'SELECT body FROM feed_record WHERE id=?',
        variables: [Variable(record['id'] as String)],
      ).getSingle();
      await _enqueue(
        'feed',
        record['id'] as String,
        'UPSERT',
        jsonDecode(saved.read<String>('body')) as Map<String, dynamic>,
      );
    }
  });
  Future<void> remove(String kind, String id) => transaction(() async {
    final row = await customSelect(
      'SELECT * FROM ${_table(kind)} WHERE id=?',
      variables: [Variable(id)],
    ).getSingleOrNull();
    if (row == null) return;
    final value = _value(kind, row);
    value['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await customStatement('DELETE FROM ${_table(kind)} WHERE id=?', [id]);
    await _enqueue(kind, id, 'DELETE', value);
    if (kind == 'bookmark') await _removeHighlightRecords(id);
    // Note history remains a historical event; a deleted note is not re-created.
  });
}

// Device/guest and account databases intentionally coexist on distinct executors.
// Separate runtime types also let Drift keep detecting accidental duplicate
// active instances within each role.
class _AccountLocalStore extends LocalStore {
  _AccountLocalStore(super.executor);
}

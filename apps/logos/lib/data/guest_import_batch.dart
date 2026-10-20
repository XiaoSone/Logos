import 'local_store.dart';

/// Prepares a durable queue snapshot for import. Account activation and network
/// dispatch belong to the future login lifecycle, not to guest storage writes.
class GuestImportBatch {
  GuestImportBatch(List<PendingChange> changes)
    : changes = List.unmodifiable(changes) {
    if (changes.isEmpty ||
        changes.length > 100 ||
        changes.map((c) => c.clientKey).toSet().length != changes.length) {
      throw ArgumentError('批次需要 1–100 个不同的 clientKey');
    }
  }

  final List<PendingChange> changes;

  List<Map<String, dynamic>> items(String Function(String) referenceForId) =>
      changes.map((change) {
        final value = change.value;
        final type = switch (change.kind) {
          'bookmark' => 'BOOKMARK',
          'note' => 'NOTE',
          'progress' => 'PROGRESS',
          'feed' => 'FEED_RECORD',
          _ => throw ArgumentError.value(change.kind, 'kind'),
        };
        if (change.kind == 'feed' && value['type'] != 'SCRIPTURE_SHARED') {
          throw ArgumentError('仅导入显式分享记录');
        }
        final ids = change.kind == 'bookmark'
            ? [value['verseId'] as String]
            : ((value['verseIds'] as List?) ?? []).cast<String>();
        final updated = value['updatedAt'] ?? value['createdAt'];
        if (updated is! String) throw ArgumentError('队列缺少时间戳');
        return <String, dynamic>{
          'clientKey': change.clientKey,
          'revision': change.revision,
          'type': type,
          'operation': change.operation,
          'createdAt': value['createdAt'] ?? updated,
          'updatedAt': updated,
          if (change.kind != 'progress')
            'verseRefs': ids.map(referenceForId).toList(),
          if (change.kind == 'bookmark') ...{
            'color': value['color'],
            'note': value['note'],
          },
          if (change.kind == 'note') ...{
            'title': value['title'],
            'content': value['content'],
            'chapterRange': value['chapterRange'],
            'tags': value['tags'] ?? [],
          },
          if (change.kind == 'progress') ...{
            'bookCode': value['bookCode'],
            'chapter': value['chapter'],
            'verse': value['verse'],
          },
          if (change.kind == 'feed') ...{
            'recordType': 'SCRIPTURE_SHARED',
            'content': value['content'],
          },
        };
      }).toList();

  /// Only invoke after a successful GraphQL response. Transport errors leave the
  /// snapshot untouched; per-item failures remain queued for correction/retry.
  Future<void> acknowledge(LocalStore store, {required List<String> failed}) {
    final keys = changes.map((c) => c.clientKey).toSet();
    if (failed.any((key) => !keys.contains(key))) {
      throw ArgumentError('服务端返回了批次以外的失败项');
    }
    return store.acknowledgeChanges(
      changes.where((c) => !failed.contains(c.clientKey)).toList(),
    );
  }
}

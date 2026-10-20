import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor openConnection({String name = 'guest'}) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,120}$').hasMatch(name)) {
    throw ArgumentError('无效数据库名称');
  }
  return WebDatabase.withStorage(DriftWebStorage.indexedDb('logos_$name'));
}

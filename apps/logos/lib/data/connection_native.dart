import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openConnection({String name = 'guest'}) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,120}$').hasMatch(name)) {
    throw ArgumentError('无效数据库名称');
  }
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(directory.path, '$name.db')),
    );
  });
}

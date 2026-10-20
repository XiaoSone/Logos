import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final destination = Platform.environment['LOGOS_ACCEPTANCE_OUTPUT'];
    if (destination == null) return writeResponseData(data);
    await File(destination).writeAsString(jsonEncode(data));
  },
  onScreenshot: (name, bytes, [args]) async {
    final destination = Platform.environment['LOGOS_ACCEPTANCE_OUTPUT'];
    final directory = destination == null
        ? '../../analysis/screenshots'
        : '${File(destination).parent.path}/screenshots';
    final output = File('$directory/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes);
    return true;
  },
);

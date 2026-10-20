import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/account_remote.dart';
import '../data/guest_import_batch.dart';
import '../data/local_store.dart';

/// A guest claim is a durable ownership decision, independent of network success.
class AccountManager extends ChangeNotifier {
  AccountManager({
    required this.guest,
    CredentialStore? credentials,
    AccountRemote? remote,
    LocalStore Function(String)? openStore,
    this.retryDelay = const Duration(seconds: 30),
    this.debounceDelay = const Duration(milliseconds: 400),
  }) : credentials = credentials ?? SecureCredentialStore(),
       remote = remote ?? GraphQlAccountRemote(),
       openStore = openStore ?? LocalStore.named,
       _active = guest;
  final LocalStore guest;
  final CredentialStore credentials;
  final AccountRemote remote;
  final LocalStore Function(String) openStore;
  final Duration retryDelay;
  final Duration debounceDelay;
  LocalStore _active;
  LocalStore get store => _active;
  AccountCredential? account;
  bool transitioning = false;
  bool guestLocked = false;
  bool syncing = false;
  String? syncError;
  DateTime? lastSyncedAt;
  int pendingCount = 0;
  int uploadedCount = 0;
  String Function(String)? referenceForId;
  Future<void> Function(LocalStore)? onDataChanged;
  final Set<Future<void>> _operations = {};
  Future<void>? _syncFuture;
  Completer<void>? _transitionDone;
  Timer? _retry;
  Timer? _debounce;
  int _epoch = 0;
  bool _closed = false;
  bool _disposed = false;
  Future<void>? _closeFuture;

  Future<T> withStore<T>(Future<T> Function(LocalStore) action) async {
    if (transitioning ||
        _closed ||
        (guestLocked && identical(_active, guest))) {
      throw StateError('个人数据正在归入原账号，请稍后重试');
    }
    final done = Completer<void>();
    _operations.add(done.future);
    try {
      return await action(_active);
    } finally {
      _operations.remove(done.future);
      done.complete();
    }
  }

  Future<void> _transition(Future<void> Function() action) async {
    if (transitioning || _closed) throw StateError('账号正在切换，请稍后再试');
    transitioning = true;
    final done = Completer<void>();
    _transitionDone = done;
    _epoch++;
    _retry?.cancel();
    _debounce?.cancel();
    notifyListeners();
    try {
      await Future.wait(_operations.toList());
      await action();
    } finally {
      transitioning = false;
      done.complete();
      _transitionDone = null;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _recoverTransfer() async {
    final saved = await guest.setting('guestTransfer');
    if (saved == null) return;
    guestLocked = true;
    final claim = jsonDecode(saved) as Map<String, dynamic>;
    final name = await accountDatabaseName(
      claim['server'] as String,
      claim['userId'] as String,
    );
    final destination = openStore(name);
    try {
      await destination.adoptGuest(
        await guest.snapshot(),
        claim['transferId'] as String,
      );
      await guest.clearGuestBusiness();
      guestLocked = false;
    } finally {
      await destination.close();
    }
  }

  Future<void> restore(String server) => _transition(() async {
    await _recoverTransfer();
    final saved = await credentials.read();
    if (saved == null) return;
    AccountCredential value;
    try {
      value = AccountCredential.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );
    } on FormatException {
      syncError = '账号信息需要重新连接，本地账号数据仍保留。';
      return;
    } on TypeError {
      syncError = '账号信息需要重新连接，本地账号数据仍保留。';
      return;
    }
    if (canonicalServer(value.server) != canonicalServer(server)) {
      syncError = '服务地址已变化，请重新连接账号。';
      return;
    }
    _active = openStore(await accountDatabaseName(value.server, value.userId));
    account = value;
    pendingCount = await _active.pendingCount();
    final stamp = await _active.setting('lastSyncedAt');
    lastSyncedAt = stamp == null ? null : DateTime.tryParse(stamp);
  });

  Future<void> login({
    required String server,
    required String phone,
    required String code,
    required String invite,
    required String deviceId,
  }) async {
    await _transition(() async {
      final value = await remote.login(
        server: canonicalServer(server),
        phone: phone,
        code: code,
        invite: invite,
        deviceId: deviceId,
      );
      if (account != null &&
          (value.userId != account!.userId ||
              value.server != account!.server)) {
        throw StateError('请先退出当前账号，再连接其他账号。');
      }
      await remote.validate(value);
      if (_closed) throw StateError('账号连接已关闭');
      if (account == null) {
        await _recoverTransfer();
        await guest.setSetting(
          'guestTransfer',
          jsonEncode({
            'server': value.server,
            'userId': value.userId,
            'transferId': const Uuid().v4(),
          }),
        );
        await _recoverTransfer();
      }
      await credentials.write(jsonEncode(value.toJson()));
      if (account == null) {
        _active = openStore(
          await accountDatabaseName(value.server, value.userId),
        );
      }
      account = value;
      syncError = null;
      lastSyncedAt = null;
      pendingCount = await _active.pendingCount();
    });
    requestSync();
  }

  Future<void> logout() => _transition(() async {
    // No account database or outbox is deleted. A later account can never adopt it.
    await credentials.clear();
    await _recoverTransfer();
    if (!identical(_active, guest)) await _active.close();
    _active = guest;
    account = null;
    pendingCount = 0;
    syncError = null;
    lastSyncedAt = null;
    await guest.clearGuestBusiness();
  });

  Future<void> recoverTransfer() async {
    try {
      await _transition(_recoverTransfer);
    } catch (_) {
      syncError = '本地数据恢复尚未完成，请重试或重新启动。数据仍保留在原账号下。';
      notifyListeners();
      rethrow;
    }
  }

  void requestSync() {
    if (account == null || transitioning || _closed) return;
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, () {
      unawaited(sync());
    });
  }

  bool _current(AccountCredential value, int epoch) =>
      !_closed &&
      !transitioning &&
      _epoch == epoch &&
      identical(account, value);

  Future<void> sync() {
    if (_syncFuture != null) return _syncFuture!;
    if (account == null || transitioning || _closed || referenceForId == null) {
      return Future.value();
    }
    final value = account!;
    final epoch = _epoch;
    final future = _synchronize(value, epoch);
    _syncFuture = future;
    return future.whenComplete(() {
      if (identical(_syncFuture, future)) _syncFuture = null;
      if (account != null &&
          !_closed &&
          !transitioning &&
          !_current(value, epoch)) {
        requestSync();
      }
    });
  }

  Future<void> _synchronize(AccountCredential value, int epoch) async {
    syncing = true;
    syncError = null;
    uploadedCount = 0;
    _retry?.cancel();
    notifyListeners();
    try {
      await remote.validate(value);
      final attempted = <String>{};
      final failures = <String>{};
      while (_current(value, epoch)) {
        final changes = await withStore(
          (store) => store.pendingChanges(excluding: attempted),
        );
        if (changes.isEmpty) break;
        final batch = GuestImportBatch(changes);
        final failed = await remote.upload(value, batch.items(referenceForId!));
        if (!_current(value, epoch)) return;
        await withStore((store) => batch.acknowledge(store, failed: failed));
        attempted.addAll(changes.map((c) => c.revision));
        failures.addAll(failed);
        uploadedCount += changes.length - failed.length;
        pendingCount = await withStore((store) => store.pendingCount());
        notifyListeners();
      }
      if (!_current(value, epoch)) return;
      final cloud = await remote.fetch(value);
      if (!_current(value, epoch)) return;
      await withStore((store) async {
        await store.replaceSynced(cloud);
        lastSyncedAt = DateTime.now().toUtc();
        await store.setSetting('lastSyncedAt', lastSyncedAt!.toIso8601String());
        pendingCount = await store.pendingCount();
        await onDataChanged?.call(store);
      });
      if (failures.isNotEmpty) syncError = '部分数据未上传，将自动重试；请检查笔记长度或引用。';
    } catch (error) {
      if (_current(value, epoch)) {
        syncError = error.toString().replaceFirst('Bad state: ', '');
      }
    } finally {
      syncing = false;
      if (!_closed) {
        if (account != null &&
            !transitioning &&
            (syncError != null || pendingCount > 0)) {
          _retry = Timer(retryDelay, () {
            unawaited(sync());
          });
        }
        notifyListeners();
      }
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _epoch++;
    _retry?.cancel();
    _debounce?.cancel();
    await _transitionDone?.future;
    await Future.wait(_operations.toList());
    if (!identical(_active, guest)) await _active.close();
    await guest.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}

// cloud_firestore marks its references and snapshots @sealed, so the plugin
// can add members. These fakes extend Fake, whose noSuchMethod covers any it
// adds, and there's no emulator to test against instead.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// In-memory stand-ins for the Firebase SDK classes FirebaseAdminService
// uses, so it can be tested without an emulator. Each call is recorded as
// 'method path' ('update bookings/s1', 'delete galleries/s1/a.jpg') in a log
// that Firestore and Storage can share, so a test can check the order
// across both. Errors are thrown by the call whose log entry is their key.

/// Firestore holding [docs] by path ('bookings/s1', 'site/home').
class FakeFirestore extends Fake implements FirebaseFirestore {
  FakeFirestore({List<String>? log}) : log = log ?? [];

  final List<String> log;

  /// Documents by path. Writes store FieldValue.serverTimestamp() as
  /// [serverTime]. After changing them directly, call [notifyChanged].
  final docs = <String, Map<String, dynamic>>{};

  /// What each set() and update() was given, sentinels and all, in order.
  final writes = <({String call, Map<Object, Object?> data})>[];

  /// Thrown by the call logged as the key ('set site/home'), every time.
  /// For snapshots(), the stream fails when listened to.
  final errors = <String, Object>{};

  /// While set, writes wait for it, as they do offline (and fail if it
  /// fails).
  Completer<void>? holdWrites;

  /// What a server timestamp is stored as.
  static const serverTime = 'server time';

  var _nextId = 1;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Has the live streams emit the current state again.
  void notifyChanged() => _changes.add(null);

  /// Fails the live streams that are running, as Firestore does (once).
  void failStreams(Object error) => _changes.addError(error);

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) => _FakeCollection(this, collectionPath);

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) => _FakeDocument(this, documentPath);

  void _record(String call) {
    log.add(call);
    final error = errors[call];
    if (error != null) throw error;
  }

  Future<void> _write(String call, Map<Object, Object?> data, void Function() apply) async {
    log.add(call);
    writes.add((call: call, data: Map.of(data)));
    final hold = holdWrites;
    if (hold != null) await hold.future;
    final error = errors[call];
    if (error != null) throw error;
    apply();
    notifyChanged();
  }

  Stream<T> _live<T>(String call, T Function() current) => Stream.multi((controller) {
        log.add(call);
        final error = errors[call];
        if (error != null) {
          controller
            ..addError(error)
            ..close();
          return;
        }
        controller.add(current());
        late final StreamSubscription<void> changes;
        changes = _changes.stream.listen(
          (_) => controller.add(current()),
          // Firestore ends a listener after its first error.
          onError: (Object error) {
            changes.cancel();
            controller
              ..addError(error)
              ..close();
          },
        );
        controller.onCancel = changes.cancel;
      });

  /// [data] applied to [doc]: deletes removed, server timestamps filled in.
  static Map<String, dynamic> _apply(Map<String, dynamic> doc, Map<Object, Object?> data) {
    final result = Map.of(doc);
    data.forEach((key, value) {
      if (value == FieldValue.delete()) {
        result.remove(key);
      } else {
        result[key as String] = value == FieldValue.serverTimestamp() ? serverTime : value;
      }
    });
    return result;
  }
}

class _FakeCollection extends Fake implements CollectionReference<Map<String, dynamic>> {
  _FakeCollection(this._db, this.path);

  final FakeFirestore _db;

  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    if (path != null) return _FakeDocument(_db, '${this.path}/$path');
    final id = 'auto-${_db._nextId++}';
    _db.log.add('new id ${this.path}/$id');
    return _FakeDocument(_db, '${this.path}/$id');
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) =>
      _db._live('snapshots $path', () {
        return _FakeQuerySnapshot([
          for (final MapEntry(:key, :value) in _db.docs.entries)
            if (key.startsWith('$path/') && !key.substring(path.length + 1).contains('/'))
              _FakeQueryDocument(key.split('/').last, Map.of(value)),
        ]);
      });
}

class _FakeDocument extends Fake implements DocumentReference<Map<String, dynamic>> {
  _FakeDocument(this._db, this.path);

  final FakeFirestore _db;

  @override
  final String path;

  @override
  String get id => path.split('/').last;

  Map<String, dynamic>? get _data {
    final data = _db.docs[path];
    return data == null ? null : Map.of(data);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    _db._record('get $path');
    return _FakeSnapshot(id, _data);
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) =>
      _db._live('snapshots $path', () => _FakeSnapshot(id, _data));

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      _db._write('set $path', data, () => _db.docs[path] = FakeFirestore._apply({}, data));

  // firestore.rules read the document's status before an update or a
  // delete, which fails when there's none, so both are refused.
  @override
  Future<void> update(Map<Object, Object?> data) => _db._write('update $path', data, () {
        final doc = _db.docs[path];
        if (doc == null) throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
        _db.docs[path] = FakeFirestore._apply(doc, data);
      });

  @override
  Future<void> delete() => _db._write('delete $path', const {}, () {
        if (_db.docs.remove(path) == null) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
        }
      });
}

class _FakeSnapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeSnapshot(this.id, this._data);

  @override
  final String id;
  final Map<String, dynamic>? _data;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;
}

class _FakeQuerySnapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _FakeQuerySnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class _FakeQueryDocument extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeQueryDocument(this.id, this._data);

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  bool get exists => true;

  @override
  Map<String, dynamic> data() => _data;
}

/// Storage holding [objects] by full path ('galleries/s1/IMG_1.jpg').
class FakeStorage extends Fake implements FirebaseStorage {
  FakeStorage({List<String>? log}) : log = log ?? [];

  final List<String> log;

  /// Objects by full path, with their content types.
  final objects = <String, String?>{};

  /// Thrown by the call logged as the key ('delete galleries/s1/a.jpg',
  /// 'putData galleries/s1/a.jpg'), every time. Uploads throw it as they
  /// start.
  final errors = <String, Object>{};

  /// Every upload started, in order.
  final tasks = <FakeUploadTask>[];

  /// The most getDownloadURL and delete calls running at once.
  var mostRunning = 0;
  var _running = 0;

  @override
  Reference ref([String? path]) => FakeReference(this, path ?? '');

  void _record(String call) {
    log.add(call);
    final error = errors[call];
    if (error != null) throw error;
  }

  /// [body] after a turn of the event loop, counting how many run at once.
  Future<T> _run<T>(String call, T Function() body) async {
    _record(call);
    mostRunning = max(mostRunning, ++_running);
    try {
      await Future<void>.delayed(Duration.zero);
      return body();
    } finally {
      _running--;
    }
  }
}

FirebaseException _storageError(String code) => FirebaseException(plugin: 'firebase_storage', code: code);

class FakeReference extends Fake implements Reference {
  FakeReference(this._storage, this.fullPath);

  final FakeStorage _storage;

  @override
  final String fullPath;

  @override
  String get name => fullPath.split('/').last;

  @override
  Reference child(String path) => FakeReference(_storage, '$fullPath/$path');

  /// One level, like Storage: the objects directly inside, and a prefix for
  /// each subfolder.
  @override
  Future<ListResult> listAll() async {
    _storage._record('listAll $fullPath');
    final prefix = '$fullPath/';
    final items = <Reference>[];
    final folders = <String>{};
    for (final path in _storage.objects.keys) {
      if (!path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        items.add(FakeReference(_storage, path));
      } else {
        folders.add('$prefix${rest.substring(0, slash)}');
      }
    }
    return _FakeListResult(items, [for (final folder in folders) FakeReference(_storage, folder)]);
  }

  @override
  Future<String> getDownloadURL() => _storage._run('getDownloadURL $fullPath', () {
        if (!_storage.objects.containsKey(fullPath)) throw _storageError('object-not-found');
        return 'https://storage.example.com/$fullPath';
      });

  @override
  Future<FullMetadata> getMetadata() async {
    _storage._record('getMetadata $fullPath');
    if (!_storage.objects.containsKey(fullPath)) throw _storageError('object-not-found');
    return _FakeMetadata();
  }

  @override
  Future<void> delete() => _storage._run('delete $fullPath', () {
        if (!_storage.objects.containsKey(fullPath)) throw _storageError('object-not-found');
        _storage.objects.remove(fullPath);
      });

  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) => _put('putData', data, metadata);

  @override
  UploadTask putBlob(dynamic blob, [SettableMetadata? metadata]) => _put('putBlob', blob as Object, metadata);

  UploadTask _put(String method, Object data, SettableMetadata? metadata) {
    _storage._record('$method $fullPath');
    final task = FakeUploadTask(this, data, metadata);
    _storage.tasks.add(task);
    return task;
  }
}

class _FakeListResult extends Fake implements ListResult {
  _FakeListResult(this.items, this.prefixes);

  @override
  final List<Reference> items;

  @override
  final List<Reference> prefixes;
}

class _FakeMetadata extends Fake implements FullMetadata {}

/// One upload: it runs until the test calls [report], [succeed] or [fail].
/// Like Storage's, a failure reaches both its Future and its events.
class FakeUploadTask extends Fake implements UploadTask {
  FakeUploadTask(this.ref, this.data, this.metadata);

  final FakeReference ref;
  final Object data;
  final SettableMetadata? metadata;

  final _events = StreamController<TaskSnapshot>.broadcast(sync: true);
  final _result = Completer<TaskSnapshot>();

  /// How many times cancel() was called.
  var cancelCalls = 0;

  /// If set, cancel()'s own Future fails with it.
  Object? cancelError;

  /// Whether anything listens to the progress events.
  bool get isWatched => _events.hasListener;

  void report(int bytesTransferred, int totalBytes) => _events.add(_FakeTaskSnapshot(bytesTransferred, totalBytes));

  /// Stores the photo and finishes.
  void succeed() {
    ref._storage.objects[ref.fullPath] = metadata?.contentType;
    _events.close();
    _result.complete(_FakeTaskSnapshot(1, 1));
  }

  /// Fails with Storage's [code] ('unauthorized', 'canceled', ...).
  void fail(String code) {
    final error = _storageError(code);
    _events
      ..addError(error)
      ..close();
    _result.completeError(error);
  }

  @override
  Stream<TaskSnapshot> get snapshotEvents => _events.stream;

  @override
  Future<bool> cancel() {
    cancelCalls++;
    final error = cancelError;
    return error == null ? Future.value(true) : Future.error(error);
  }

  @override
  Future<S> then<S>(FutureOr<S> Function(TaskSnapshot value) onValue, {Function? onError}) =>
      _result.future.then(onValue, onError: onError);
}

class _FakeTaskSnapshot extends Fake implements TaskSnapshot {
  _FakeTaskSnapshot(this.bytesTransferred, this.totalBytes);

  @override
  final int bytesTransferred;

  @override
  final int totalBytes;
}

/// FirebaseAuth signed in as [uid], or signed out (set [currentUser] to
/// null).
class FakeFirebaseAuth extends Fake implements FirebaseAuth {
  FakeFirebaseAuth({String? uid}) : currentUser = uid == null ? null : _FakeUser(uid);

  @override
  User? currentUser;
}

class _FakeUser extends Fake implements User {
  _FakeUser(this.uid);

  @override
  final String uid;
}

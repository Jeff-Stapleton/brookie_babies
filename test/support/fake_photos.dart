import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the network when widget tests show photos with NetworkImage
/// (flutter_test's own client fails every request).
///
/// A photo whose URL is in [broken] fails at once, like a missing file. Any
/// other photo's download never finishes, so it stays loading for the whole
/// test, as on a slow connection.
///
/// Painting debug variables must be back to their defaults when a test's body
/// ends, so call [stop] in the test itself (try/finally), not in a tear-down.
class FakePhotoServer {
  final broken = <Uri>{};
  final requested = <Uri>[];
  final _responses = <Uri, List<int>>{};
  final _waiting = <Uri, Completer<HttpClientRequest>>{};

  void start() {
    requested.clear();
    _responses.clear();
    _waiting.clear();
    // Nothing loaded (or still loading) in an earlier test carries over.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    debugNetworkImageHttpClientProvider = () => _Client(this);
  }

  void stop() => debugNetworkImageHttpClientProvider = null;

  /// Completes a pending request for [url], or makes a later one succeed.
  void serve(Uri url, List<int> bytes) {
    _responses[url] = bytes;
    _waiting.remove(url)?.complete(_OkRequest(bytes));
  }

  Future<HttpClientRequest> _request(Uri url) {
    requested.add(url);
    if (broken.contains(url)) return Future.value(_NotFoundRequest());
    final bytes = _responses[url];
    if (bytes != null) return Future.value(_OkRequest(bytes));
    return (_waiting[url] ??= Completer<HttpClientRequest>()).future;
  }
}

class _Client extends Fake implements HttpClient {
  _Client(this._server);

  final FakePhotoServer _server;

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _server._request(url);
}

class _OkRequest extends Fake implements HttpClientRequest {
  _OkRequest(this.bytes);

  final List<int> bytes;

  @override
  Future<HttpClientResponse> close() async => _OkResponse(bytes);
}

class _OkResponse extends Stream<List<int>> implements HttpClientResponse {
  _OkResponse(this.bytes);

  final List<int> bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NotFoundRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _NotFoundResponse();
}

class _NotFoundResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.notFound;

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;
}

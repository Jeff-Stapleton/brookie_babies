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

  void start() {
    // Nothing loaded (or still loading) in an earlier test carries over.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    debugNetworkImageHttpClientProvider = () => _Client(this);
  }

  void stop() => debugNetworkImageHttpClientProvider = null;
}

class _Client extends Fake implements HttpClient {
  _Client(this._server);

  final FakePhotoServer _server;

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _server.broken.contains(url) ? Future.value(_NotFoundRequest()) : Completer<HttpClientRequest>().future;
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

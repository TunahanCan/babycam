import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/client/media/client_video_viewer.dart';

void main() {
  testWidgets('video stream frame gelmezse timeout ve reconnect isaretler',
      (tester) async {
    final stream = StreamController<List<int>>();
    addTearDown(stream.close);
    final timedOut = Completer<void>();
    final reconnected = Completer<void>();

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 120,
        height: 90,
        child: ClientVideoViewer(
          pairedServerHost: '127.0.0.1',
          pairedServerPort: 8080,
          url: 'http://127.0.0.1:8080/video',
          clientFactory: () => _FakeHttpClient(
            _FakeHttpClientResponse(stream.stream),
          ),
          connectTimeout: const Duration(milliseconds: 200),
          readTimeout: const Duration(milliseconds: 40),
          retryDelay: const Duration(seconds: 30),
          onStreamTimeout: () {
            if (!timedOut.isCompleted) timedOut.complete();
          },
          onReconnectAttempt: () {
            if (!reconnected.isCompleted) reconnected.complete();
          },
        ),
      ),
    ));

    stream.add('--frame\r\nContent-Length: 0\r\n\r\n\r\n'.codeUnits);
    for (var i = 0;
        i < 20 && (!timedOut.isCompleted || !reconnected.isCompleted);
        i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(timedOut.isCompleted, isTrue);
    expect(reconnected.isCompleted, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.response);

  final HttpClientResponse response;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(response);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.response);

  final HttpClientResponse response;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this._stream);

  final Stream<List<int>> _stream;

  @override
  final int statusCode = HttpStatus.ok;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

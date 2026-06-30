import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/client/media/client_video_viewer.dart';

void main() {
  testWidgets('frame yokken loading, hata varken kapalı kamera ikonu gösterir',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 120,
        height: 90,
        child: ClientVideoViewer(frame: null),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.videocam_off_rounded), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 120,
        height: 90,
        child: ClientVideoViewer(
          frame: null,
          error: StateError('stream failed'),
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);
  });
}

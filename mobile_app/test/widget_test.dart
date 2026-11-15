import 'package:flutter_test/flutter_test.dart';
import 'package:media_verify_ai/main.dart';

void main() {
  testWidgets('VeriLens app renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MediaVerifyApp());
    expect(find.text('VeriLens'), findsOneWidget);
  });
}
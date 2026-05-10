import 'package:flutter_test/flutter_test.dart';
import 'package:asd_intervention/main.dart';

void main() {
  testWidgets('App renders title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ASDInterventionApp());

    // Verify that the app title is displayed
    expect(find.text('Social Skills Adventure'), findsOneWidget);
  });
}

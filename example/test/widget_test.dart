// Basic smoke test for the saf mini file manager example.

import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('renders the initial empty state', (WidgetTester tester) async {
    await tester.pumpWidget(const MiniFileManagerApp());

    expect(find.text('SAF Mini File Manager'), findsOneWidget);
    expect(find.text('No folder selected'), findsOneWidget);
    expect(find.text('Pick'), findsOneWidget);
  });
}

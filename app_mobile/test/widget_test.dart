// SKU+ Widget tests

import 'package:flutter_test/flutter_test.dart';

import 'package:app_mobile/main.dart';

void main() {
  testWidgets('App loads splash screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SkuPlusApp());

    // Verify that SKU+ title is shown
    expect(find.text('SKU+'), findsOneWidget);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keydrop_piano/app.dart';

void main() {
  testWidgets('KeyDropApp builds smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const ProviderScope(child: KeyDropApp()));
    expect(find.text('键落钢琴'), findsOneWidget);
  });
}

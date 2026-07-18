import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:karlash/main.dart';
import 'package:karlash/repository/tracking_repository.dart';

void main() {
  testWidgets('App renders login screen smoke test',
      (WidgetTester tester) async {
    final repository = MockTrackingRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => TrackingProvider(repository: repository),
        child: const MultiCamTrackingApp(),
      ),
    );

    // Verify that the login screen title is rendered.
    expect(find.text('INSIGHT'), findsOneWidget);
    expect(find.text('STAFF LOGIN'), findsOneWidget);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'shows backend setup state when no build configuration is supplied',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const ProviderScope(child: LabWizardApp()));
      await tester.pumpAndSettle();
      expect(find.text('backend not configured'), findsOneWidget);
    },
  );
}

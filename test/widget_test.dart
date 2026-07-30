import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsls_app/screens/safety_disclaimer_page.dart';

void main() {
  group('SafetyDisclaimerPage', () {
    testWidgets('shows no accept button when opened from Settings',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SafetyDisclaimerPage()),
      );

      expect(find.text('Important Safety Information'), findsOneWidget);
      expect(find.text('I Understand and Accept'), findsNothing);
    });

    testWidgets('shows an accept button when used as a first-run gate',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SafetyDisclaimerPage(
            requireAcceptance: true,
            onAccepted: () {},
          ),
        ),
      );

      expect(find.text('I Understand and Accept'), findsOneWidget);
    });

    testWidgets('invokes onAccepted when the gate is accepted', (tester) async {
      // Regression: the callback was originally wired through the splash
      // screen's State, which pushReplacement had already disposed, so the
      // button did nothing.
      var accepted = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SafetyDisclaimerPage(
            requireAcceptance: true,
            onAccepted: () => accepted++,
          ),
        ),
      );

      await tester.tap(find.text('I Understand and Accept'));
      await tester.pump();

      expect(accepted, 1);
    });

    testWidgets('gate cannot be dismissed with the back button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SafetyDisclaimerPage(
            requireAcceptance: true,
            onAccepted: () {},
          ),
        ),
      );

      expect(find.byType(BackButton), findsNothing);

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:volleylive/main.dart';

void main() {
  testWidgets('VolleyLiveApp renders ModeSelectScreen with Phone A and Phone B options', (WidgetTester tester) async {
    await tester.pumpWidget(const VolleyLiveApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('VolleyLive Pro'), findsOneWidget);
    expect(find.text('PHONE B: PILOT / SĘDZIA + REŻYSERKA'), findsOneWidget);
    expect(find.text('PHONE A: KAMERA (STATYW)'), findsOneWidget);
    expect(find.text('TRYB STATYSTYKA (STREFY BOISKA)'), findsOneWidget);
  });
}

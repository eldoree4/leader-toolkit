import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leader_toolkit/main.dart';

void main() {
  testWidgets('menampilkan aplikasi offline', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const LeaderToolkitApp());
    await tester.pumpAndSettle();

    expect(find.text('Ringkasan produksi'), findsOneWidget);
  });
}

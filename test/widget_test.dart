import 'package:flutter_test/flutter_test.dart';
import 'package:leader_toolkit/main.dart';

void main() {
  testWidgets('shows setup instructions without Supabase build configuration', (tester) async {
    await tester.pumpWidget(const LeaderToolkitApp());
    expect(find.textContaining('Konfigurasi Supabase belum tersedia'), findsOneWidget);
  });
}

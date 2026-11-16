import 'package:flutter_test/flutter_test.dart';
import 'package:dentehr_clinic/main.dart';

void main() {
  testWidgets('builds', (tester) async {
    await tester.pumpWidget(const DentehrClinicApp());
    expect(find.byType(DentehrClinicApp), findsOneWidget);
  });
}

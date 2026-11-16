import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dentehr_clinic/odontogram/odontogram.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OdontogramModel Tests (GUI & TUI)', () {
    test('Initial state has no abnormal or missing teeth', () {
      final model = OdontogramModel();
      expect(model.dmftIndex, 0);
      expect(model.abnormalTeeth, isEmpty);
      expect(model.missingTeeth, isEmpty);
      expect(model.treatedTeeth, isEmpty);
      expect(model.kennedyClassification, 'No Kennedy Classification');
      expect(model.periodontalDiagnosis, 'Normal / None');
    });

    test('GUI: Cycle tooth conditions by touch', () {
      final model = OdontogramModel();
      expect(model.getCondition('11'), ToothCondition.none);

      model.cycleToothCondition('11');
      expect(model.getCondition('11'), ToothCondition.abnormal);

      model.cycleToothCondition('11');
      expect(model.getCondition('11'), ToothCondition.missing);

      model.cycleToothCondition('11');
      expect(model.getCondition('11'), ToothCondition.treated);

      model.cycleToothCondition('11');
      expect(model.getCondition('11'), ToothCondition.none);
    });

    test('TUI: Editable tooth numbers by keyboard input', () {
      final model = OdontogramModel();

      // Keyboard input into Decayed field
      model.setTeethForCategory('Decayed', '11, 26, 47');
      expect(model.getCondition('11'), ToothCondition.abnormal);
      expect(model.getCondition('26'), ToothCondition.abnormal);
      expect(model.getCondition('47'), ToothCondition.abnormal);
      expect(model.getTeethStringForCategory('Decayed'), '11, 26, 47');

      // Keyboard input into Missing field
      model.setTeethForCategory('Missing', '18, 28, 36');
      expect(model.getCondition('18'), ToothCondition.missing);
      expect(model.getCondition('36'), ToothCondition.missing);
      expect(model.kennedyClassification, 'Class I');

      // Keyboard input into Treated field
      model.setTeethForCategory('Treated', '16, 46');
      expect(model.getCondition('16'), ToothCondition.treated);
      expect(model.getCondition('46'), ToothCondition.treated);

      // DMFT index calculated from TUI entries
      // 3 decayed + 3 missing + 2 treated = 8
      expect(model.dmftIndex, 8);

      // Keyboard input into Mobility field
      model.setTeethForCategory('Mobility', '11, 41');
      expect(model.getFinding('11').mobility, isTrue);
      expect(model.getFinding('41').mobility, isTrue);
      expect(model.periodontalDiagnosis, 'Generalized Periodontitis');

      // Keyboard input into Calculus field (Yes / No toggle)
      model.setTeethForCategory('Calculus', 'yes');
      expect(model.hasCalculus, isTrue);
      expect(model.getTeethStringForCategory('Calculus'), 'Yes');

      model.setTeethForCategory('Calculus', 'no');
      expect(model.hasCalculus, isFalse);
      expect(model.getTeethStringForCategory('Calculus'), 'No');
    });

    test('DMFT and Kennedy classification calculation', () {
      final model = OdontogramModel();
      model.setCondition('11', ToothCondition.abnormal);
      model.setCondition('36', ToothCondition.missing);
      model.setCondition('21', ToothCondition.treated);

      expect(model.dmftIndex, 3);
      expect(model.kennedyClassification, 'Class I');
    });

    test('Caries evaluation: Class 1 and Class 2', () {
      final class1 = OdontogramModel.evaluateCaries(['occlusal']);
      expect(class1.diagnosis, 'Pit and fissure caries');
      expect(class1.treatment.contains('Class 1 restoration'), isTrue);

      final class2 = OdontogramModel.evaluateCaries(['mesial', 'occlusal']);
      expect(class2.diagnosis, 'Proximal caries');
      expect(class2.treatment.contains('Class 2 restoration'), isTrue);
    });

    test('Serialization and Patient Record Roundtrip', () {
      final model = OdontogramModel();
      model.setCondition('14', ToothCondition.abnormal);
      final finding = model.getFinding('14');
      finding.isDecayed = true;
      finding.decayAreas.add('occlusal');
      finding.mobility = true;

      model.hasCalculus = true;

      final diagnosisText = model.toDiagnosisSummaryString();
      final treatmentText = model.toTreatmentPlanSummaryString();
      expect(diagnosisText, contains('Calculus: Yes'));
      final embedded = model.embedInString(treatmentText);

      final row = {
        'phone': '9876543210',
        'diagnosis': diagnosisText,
        'treatment_plan': embedded,
        'appointment': '2026-11-10',
      };

      final parsed = OdontogramModel.fromPatientRecord(row);
      expect(parsed.getCondition('14'), ToothCondition.abnormal);
      expect(parsed.getFinding('14').isDecayed, isTrue);
      expect(parsed.getFinding('14').decayAreas, contains('occlusal'));
      expect(parsed.getFinding('14').mobility, isTrue);
      expect(parsed.hasCalculus, isTrue);
    });

    test('PDF Export generates valid PDF bytes', () async {
      final model = OdontogramModel();
      model.setCondition('11', ToothCondition.abnormal);
      model.setCondition('16', ToothCondition.missing);
      model.setCondition('26', ToothCondition.treated);

      final pdfBytes = await OdontogramPdfService.generatePdfBytes(
        model: model,
        phone: '1234567890',
        appointment: '2026-11-10 10:00 AM',
        clinic: 'Test Dental Clinic',
      );

      expect(pdfBytes, isNotEmpty);
      final header = String.fromCharCodes(pdfBytes.take(5));
      expect(header, '%PDF-');
    });

    testWidgets('Calculus toggle Yes/No in UI', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final model = OdontogramModel();
      expect(model.hasCalculus, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OdontogramWidget(model: model),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the "Yes" text button in Calculus card and tap it
      final yesText = find.text('Yes').first;
      await tester.tap(yesText);
      await tester.pumpAndSettle();

      expect(model.hasCalculus, isTrue);

      // Find "No" text button and tap it
      final noText = find.text('No').first;
      await tester.tap(noText);
      await tester.pumpAndSettle();

      expect(model.hasCalculus, isFalse);
    });

    testWidgets('Tooth touch opens assessment dialog with Missing and Treated options', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final model = OdontogramModel();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OdontogramWidget(model: model),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Odontogram CustomPaint and calculate position of tooth 11
      final customPaintFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is OdontogramPainter,
      ).first;
      final paintTopLeft = tester.getTopLeft(customPaintFinder);
      final paintSize = tester.getSize(customPaintFinder);
      final scaleX = paintSize.width / 300.0;
      final scaleY = paintSize.height / 380.0;
      final scale = scaleX < scaleY ? scaleX : scaleY;
      final offsetX = (paintSize.width - 300.0 * scale) / 2;
      final offsetY = (paintSize.height - 380.0 * scale) / 2;
      final tooth11Pos = paintTopLeft + Offset(offsetX + 125 * scale, offsetY + 35 * scale);

      await tester.tapAt(tooth11Pos);
      await tester.pumpAndSettle();

      // Check that Tooth Assessment dialog opened
      expect(find.textContaining('Assessment'), findsOneWidget);

      // Check that 'Missing' and 'Treated' chips are present in the dialog
      expect(find.widgetWithText(ChoiceChip, 'Missing'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Treated'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Normal'), findsOneWidget);

      // Select 'Missing'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Missing'));
      await tester.pumpAndSettle();

      // Tap 'Apply Changes'
      await tester.tap(find.text('Apply Changes'));
      await tester.pumpAndSettle();

      // Verify tooth 11 is now missing!
      expect(model.getCondition('11'), ToothCondition.missing);
      expect(model.missingTeeth, contains('11'));
    });
  });
}

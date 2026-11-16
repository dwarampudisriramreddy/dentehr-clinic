import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/odontogram_model.dart';
import '../widgets/odontogram_painter.dart';

class OdontogramPdfService {
  static Future<Uint8List> generatePdfBytes({
    required OdontogramModel model,
    String? phone,
    String? appointment,
    String? clinic,
  }) async {
    // 1. Render Odontogram to high-res image
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const renderSize = Size(600, 780);

    // Paint background
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & renderSize, bgPaint);

    final painter = OdontogramPainter(
      model: model,
      showLabels: true,
      showCalculus: true,
    );
    painter.paint(canvas, renderSize);

    final picture = recorder.endRecording();
    final img = await picture.toImage(600, 780);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final chartImageBytes = byteData!.buffer.asUint8List();

    // 2. Build PDF Document
    final pdf = pw.Document();
    final chartImage = pw.MemoryImage(chartImageBytes);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'DENTAL EHR RECORD',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.teal800,
                    ),
                  ),
                  pw.Text(
                    'Patient Odontogram & Clinical Assessment Report',
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Date: ${DateTime.now().toLocal().toString().split('.')[0]}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  if (clinic != null && clinic.isNotEmpty)
                    pw.Text('Clinic: $clinic', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 1.5, color: PdfColors.teal700),
          pw.SizedBox(height: 10),

          // Patient info box
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Patient Phone: ${phone ?? 'N/A'}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Text('Appointment: ${appointment ?? 'Not scheduled'}', style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Dentition: ${model.dentition.displayName}', style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Odontogram Chart Section
          pw.Text('Dental Odontogram Chart', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Container(
              height: 260,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Image(chartImage, fit: pw.BoxFit.contain),
            ),
          ),
          pw.SizedBox(height: 8),

          // Legend for PDF
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              _pdfLegend(PdfColors.blueGrey100, 'Normal'),
              pw.SizedBox(width: 10),
              _pdfLegend(PdfColors.red400, 'Abnormal'),
              pw.SizedBox(width: 10),
              _pdfLegend(PdfColors.yellow300, 'Caries / Decay'),
              pw.SizedBox(width: 10),
              _pdfLegend(PdfColors.grey800, 'Missing'),
              pw.SizedBox(width: 10),
              _pdfLegend(PdfColors.green500, 'Treated'),
              pw.SizedBox(width: 10),
              _pdfLegend(PdfColors.amber, 'Calculus'),
            ],
          ),
          pw.SizedBox(height: 14),

          // Indices & Classifications Table
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.teal50),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('DMFT Index', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('Kennedy Classification', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('Periodontal Assessment', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('${model.dmftIndex} (Abnormal: ${model.abnormalTeeth.length}, Missing: ${model.missingTeeth.length}, Treated: ${model.treatedTeeth.length})', style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(model.kennedyClassification, style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(model.periodontalDiagnosis, style: const pw.TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // Diagnosis Summary
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.red200),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              color: PdfColors.red50,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Diagnosis Summary:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.red900)),
                pw.SizedBox(height: 4),
                pw.Text(model.toDiagnosisSummaryString(), style: const pw.TextStyle(fontSize: 10, height: 1.3)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),

          // Treatment Plan Summary
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.teal200),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              color: PdfColors.teal50,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Recommended Treatment Plan:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.teal900)),
                pw.SizedBox(height: 4),
                pw.Text(model.toTreatmentPlanSummaryString(), style: const pw.TextStyle(fontSize: 10, height: 1.3)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),

          // Chief Complaints (if any)
          if (model.complaints.isNotEmpty) ...[
            pw.Text('Chief Complaints:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: model.complaints.asMap().entries.map((e) {
                final c = e.value;
                return pw.Text(
                  '${e.key + 1}. Complains of ${c.type} in tooth region ${c.toothId} since ${c.duration}',
                  style: const pw.TextStyle(fontSize: 10),
                );
              }).toList(),
            ),
            pw.SizedBox(height: 10),
          ],

          // Footer
          pw.Spacer(),
          pw.Divider(color: PdfColors.grey300),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Generated by Dentehr Dental System', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text('Confidential Medical Record', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pdfLegend(PdfColor color, String text) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 8,
          height: 8,
          color: color,
        ),
        pw.SizedBox(width: 3),
        pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
      ],
    );
  }

  static Future<void> printOrShare({
    required BuildContext context,
    required OdontogramModel model,
    String? phone,
    String? appointment,
    String? clinic,
  }) async {
    final pdfBytes = await generatePdfBytes(
      model: model,
      phone: phone,
      appointment: appointment,
      clinic: clinic,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'odontogram_${phone ?? 'patient'}.pdf',
    );
  }
}

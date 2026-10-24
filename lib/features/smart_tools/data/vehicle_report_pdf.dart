import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/askodox_pdf_text.dart';
import '../domain/meter_math.dart';
import 'vision_inspection_repository.dart';

/// JPEG / PNG only: the PDF library cannot embed other formats (e.g. HEIC).
bool askodoxPdfCanEmbed(Uint8List b) =>
    (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) || (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47);

/// A4 PDF of a guided 4-side vehicle walk-around: the user's own details, the four
/// photos, and the AI report exactly as the backend returned it (seen / likely /
/// cannot confirm / checks / warnings). Always states that it is a visual
/// observation, never a roadworthiness, fitness or insurance certificate.
Future<Uint8List> askodoxVehicleReportPdf({
  required AskodoxInspectionReport report,
  required Map<String, Uint8List> photos,
  required String date,
  String vehicle = '',
  String odometer = '',
  bool te = false,
  bool compress = true,
}) async {
  const width = 539.0; // A4 minus margins
  const body = pw.TextStyle(fontSize: 9.5);
  const head = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);
  final g = AskodoxPdfText();

  String label(String en, String teText) => te ? teText : en;
  final sections = <(String, List<String>)>[
    (label('Seen in the photos', 'ఫోటోలలో కనిపించింది'),
        [for (final f in report.observed) '${f.finding}${f.detail == null ? '' : ' - ${f.detail}'}']),
    (label('Likely (not confirmed)', 'అవకాశం ఉంది (నిర్ధారణ కాదు)'),
        [for (final f in report.inferred) '${f.finding}${f.detail == null ? '' : ' - ${f.detail}'}']),
    (label('Cannot be confirmed from photos', 'ఫోటోల నుండి నిర్ధారించలేము'), report.notVerifiable),
    (label('Get these checked', 'ఇవి తనిఖీ చేయించండి'), report.recommendedChecks),
    (label('Safety warnings', 'భద్రతా హెచ్చరికలు'), report.safetyWarnings),
    (label('Photos that would help', 'ఇంకా ఈ ఫోటోలు సహాయపడతాయి'), report.needsMoreEvidence),
    (label('Limits of this report', 'ఈ రిపోర్ట్ పరిమితులు'), report.limits),
  ];
  final disclaimer = label(
    'Visual observation from four photos by an AI model. NOT a roadworthiness, fitness, emission or insurance '
        'certificate. Have the vehicle inspected by a qualified mechanic before buying, selling or driving it.',
    'నాలుగు ఫోటోల నుండి AI చేసిన దృశ్య పరిశీలన మాత్రమే. ఇది రోడ్ యోగ్యత, ఫిట్‌నెస్, కాలుష్య లేదా ఇన్సూరెన్స్ సర్టిఫికెట్ కాదు. '
        'కొనే / అమ్మే / నడిపే ముందు అర్హత ఉన్న మెకానిక్‌తో తనిఖీ చేయించండి.',
  );

  final titleText = label('Vehicle walk-around report', 'వాహన పరిశీలన రిపోర్ట్');
  await g.want(titleText, 16, bold: true);
  await g.want(vehicle, 9.5, maxWidth: width - 100);
  await g.want(report.subject, 9.5, maxWidth: width - 100);
  await g.want(disclaimer, 9.5, bold: true, maxWidth: width);
  for (final side in askodoxVehicleSides) {
    await g.want(label(side.en, side.te), 9.5);
  }
  for (final (title, lines) in sections) {
    if (lines.isEmpty) continue;
    await g.want(title, 11, bold: true);
    for (final line in lines) {
      await g.want('- $line', 9.5, maxWidth: width);
    }
  }

  pw.Widget kv(String k, pw.Widget v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 100, child: pw.Text(k, style: body.copyWith(fontWeight: pw.FontWeight.bold))),
          pw.Expanded(child: v),
        ]),
      );

  final doc = pw.Document(compress: compress);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => [
      g.text(titleText, const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold), bold: true),
      pw.SizedBox(height: 6),
      kv('Date', pw.Text(askodoxPdfAscii(date), style: body)),
      if (vehicle.trim().isNotEmpty) kv('Vehicle (as told)', g.text(vehicle, body, maxWidth: width - 100)),
      if (odometer.trim().isNotEmpty) kv('Odometer (as told)', pw.Text('${askodoxPdfAscii(odometer)} km', style: body)),
      if ((report.subject ?? '').isNotEmpty) kv('AI saw', g.text(report.subject, body, maxWidth: width - 100)),
      kv('Result', pw.Text('${report.status} · confidence ${(report.confidence * 100).round()}% · ${report.mode} scan', style: body)),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8, color: PdfColors.red800)),
        child: g.text(disclaimer, body.copyWith(fontWeight: pw.FontWeight.bold), bold: true, maxWidth: width),
      ),
      pw.SizedBox(height: 10),
      pw.Wrap(spacing: 8, runSpacing: 8, children: [
        for (final side in askodoxVehicleSides)
          if (photos[side.id] != null && askodoxPdfCanEmbed(photos[side.id]!))
            pw.SizedBox(
              width: (width - 8) / 2,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                g.text(label(side.en, side.te), body),
                pw.Image(pw.MemoryImage(photos[side.id]!), height: 150, fit: pw.BoxFit.contain),
              ]),
            ),
      ]),
      for (final (title, lines) in sections)
        if (lines.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          g.text(title, head, bold: true),
          for (final line in lines) g.text('- $line', body, maxWidth: width),
        ],
    ],
  ));
  return doc.save();
}

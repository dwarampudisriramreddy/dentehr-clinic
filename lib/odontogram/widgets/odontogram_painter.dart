import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';
import '../data/odontogram_paths.dart';
import '../models/odontogram_model.dart';

class FlutterPathProxy implements PathProxy {
  final Path path;
  FlutterPathProxy(this.path);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}

class OdontogramGeometry {
  static final OdontogramGeometry instance = OdontogramGeometry._internal();

  final Map<String, Path> parentPaths = {};
  final Map<String, List<Path>> innerPaths = {};
  final Map<String, Path> segmentPaths = {};
  final Map<String, Rect> toothBounds = {};
  final Map<String, Offset> toothCenters = {};

  static const double baseWidth = 300.0;
  static const double baseHeight = 390.0;

  OdontogramGeometry._internal() {
    _initPaths();
  }

  void _initPaths() {
    for (final entry in kToothPaths.entries) {
      final tid = entry.key;
      final data = entry.value;

      final p = Path();
      writeSvgPathDataToPath(data.parentPath, FlutterPathProxy(p));
      parentPaths[tid] = p;
      toothBounds[tid] = p.getBounds();
      toothCenters[tid] = p.getBounds().center;

      final inners = <Path>[];
      for (final inn in data.innerPaths) {
        final ip = Path();
        writeSvgPathDataToPath(inn, FlutterPathProxy(ip));
        inners.add(ip);
      }
      innerPaths[tid] = inners;
    }

    for (final entry in kCalculusSegments.entries) {
      final sp = Path();
      writeSvgPathDataToPath(entry.value, FlutterPathProxy(sp));
      segmentPaths[entry.key] = sp;
    }
  }

  String? hitTest(Offset localPoint, Size canvasSize, List<String> visibleTeeth) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return null;

    final scaleX = canvasSize.width / baseWidth;
    final scaleY = canvasSize.height / baseHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final offsetX = (canvasSize.width - baseWidth * scale) / 2;
    final offsetY = (canvasSize.height - baseHeight * scale) / 2;

    final svgPoint = Offset(
      (localPoint.dx - offsetX) / scale,
      (localPoint.dy - offsetY) / scale,
    );

    // 1. Precise path hit test
    for (final tid in visibleTeeth) {
      final path = parentPaths[tid];
      if (path != null && path.contains(svgPoint)) {
        return tid;
      }
    }

    // 2. Proximity hit test (within 16px of tooth center or label)
    double minDistance = 22.0;
    String? closestTooth;

    for (final tid in visibleTeeth) {
      final center = toothCenters[tid];
      if (center != null) {
        final d = (center - svgPoint).distance;
        if (d < minDistance) {
          minDistance = d;
          closestTooth = tid;
        }
      }

      final data = kToothPaths[tid];
      if (data != null) {
        final labelPos = Offset(data.labelX + 5, data.labelY);
        final d = (labelPos - svgPoint).distance;
        if (d < minDistance) {
          minDistance = d;
          closestTooth = tid;
        }
      }
    }

    return closestTooth;
  }
}

class OdontogramPainter extends CustomPainter {
  final OdontogramModel model;
  final String? selectedToothId;
  final bool showLabels;
  final bool showCalculus;

  static final OdontogramGeometry geom = OdontogramGeometry.instance;

  OdontogramPainter({
    required this.model,
    this.selectedToothId,
    this.showLabels = true,
    this.showCalculus = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / OdontogramGeometry.baseWidth;
    final scaleY = size.height / OdontogramGeometry.baseHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final offsetX = (size.width - OdontogramGeometry.baseWidth * scale) / 2;
    final offsetY = (size.height - OdontogramGeometry.baseHeight * scale) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    // 1. Draw Calculus Segments
    if (showCalculus) {
      _drawCalculusSegments(canvas);
    }

    // 2. Draw Teeth
    final visibleTeeth = model.visibleTeeth;
    for (final tid in visibleTeeth) {
      _drawTooth(canvas, tid);
    }

    // 3. Draw Selected Highlight
    if (selectedToothId != null && visibleTeeth.contains(selectedToothId)) {
      _drawSelectionHighlight(canvas, selectedToothId!);
    }

    // 4. Draw Tooth Condition Markers (Mobility, Recession, Pocket)
    for (final tid in visibleTeeth) {
      _drawConditionBoxes(canvas, tid);
    }

    // 5. Draw Tooth Number Labels
    if (showLabels) {
      for (final tid in visibleTeeth) {
        _drawToothLabel(canvas, tid);
      }
    }

    canvas.restore();
  }

  void _drawCalculusSegments(Canvas canvas) {
    final isPresent = model.hasCalculus;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isPresent ? 5.5 : 2.0
      ..color = isPresent ? const Color(0xFFF59E0B) : const Color(0x339E9E9E)
      ..strokeCap = StrokeCap.round;

    for (int i = 1; i <= 6; i++) {
      final segKey = 'segment_$i';
      final path = geom.segmentPaths[segKey];
      if (path != null) {
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawTooth(Canvas canvas, String tid) {
    final parentPath = geom.parentPaths[tid];
    if (parentPath == null) return;

    final condition = model.getCondition(tid);
    final finding = model.toothFindings[tid];

    Color fillColor = const Color(0xFFE0F2FE); // Default lightblue
    Color strokeColor = Colors.black87;
    double strokeWidth = 1.0;

    switch (condition) {
      case ToothCondition.none:
        fillColor = const Color(0xFFE2E8F0);
        strokeColor = Colors.black54;
        break;

      case ToothCondition.abnormal:
        fillColor = const Color(0xFFEF4444); // Red default
        if (finding != null) {
          if (finding.specificDiagnosis == 'Pulpitis') {
            fillColor = const Color(0xFFFFB6C1); // Light pinkish red
          } else if (finding.specificDiagnosis == 'Abscess') {
            fillColor = const Color(0xFFFF9999); // Light coral red
          } else if (finding.specificDiagnosis == 'Periodontitis') {
            fillColor = const Color(0xFFFF4747); // Strong medium red
          } else if (finding.isDecayed || finding.isFracture || finding.isAttrition) {
            fillColor = const Color(0xFFFEF08A); // Yellow
            strokeColor = const Color(0xFFDC2626); // Red outline
            strokeWidth = 2.0;
          }
        }
        break;

      case ToothCondition.missing:
        fillColor = const Color(0xFF1F2937); // Dark black/grey
        strokeColor = Colors.black;
        break;

      case ToothCondition.treated:
        fillColor = const Color(0xFF22C55E); // Green
        strokeColor = const Color(0xFF15803D);
        if (finding?.hasFailure == true) {
          strokeColor = Colors.red;
          strokeWidth = 2.0;
        }
        break;
    }

    // Fill parent path
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;
    canvas.drawPath(parentPath, fillPaint);

    // Stroke parent path
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = strokeColor
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(parentPath, strokePaint);

    // Draw inner fissure paths if not missing
    if (condition != ToothCondition.missing) {
      final innerList = geom.innerPaths[tid] ?? [];
      final innerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = condition == ToothCondition.abnormal && strokeColor == const Color(0xFFDC2626)
            ? const Color(0xFF991B1B)
            : Colors.black45
        ..strokeWidth = 0.8;

      for (final ip in innerList) {
        canvas.drawPath(ip, innerPaint);
      }
    } else {
      // Draw cross (X) for missing tooth
      final bounds = geom.toothBounds[tid];
      if (bounds != null) {
        final crossPaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white70
          ..strokeWidth = 1.5;
        canvas.drawLine(bounds.topLeft, bounds.bottomRight, crossPaint);
        canvas.drawLine(bounds.topRight, bounds.bottomLeft, crossPaint);
      }
    }
  }

  void _drawSelectionHighlight(Canvas canvas, String tid) {
    final parentPath = geom.parentPaths[tid];
    if (parentPath == null) return;

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);

    canvas.drawPath(parentPath, highlightPaint);
  }

  void _drawConditionBoxes(Canvas canvas, String tid) {
    final finding = model.toothFindings[tid];
    if (finding == null) return;

    final center = geom.toothCenters[tid];
    if (center == null) return;

    // Mobility (yellow box)
    if (finding.mobility) {
      final rect = Rect.fromCenter(center: center, width: 26, height: 26);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFEAB308)
        ..strokeWidth = 1.8;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), p);
    }

    // Recession (red box)
    if (finding.recession) {
      final rect = Rect.fromCenter(center: center, width: 30, height: 30);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFEF4444)
        ..strokeWidth = 1.8;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), p);
    }

    // Pocket (pink box)
    if (finding.pocket) {
      final rect = Rect.fromCenter(center: center, width: 34, height: 34);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFEC4899)
        ..strokeWidth = 1.8;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), p);
    }
  }

  void _drawToothLabel(Canvas canvas, String tid) {
    final data = kToothPaths[tid];
    if (data == null) return;

    final isSelected = selectedToothId == tid;
    final condition = model.getCondition(tid);

    Color textColor = Colors.black87;
    if (condition == ToothCondition.abnormal) textColor = const Color(0xFFDC2626);
    if (condition == ToothCondition.treated) textColor = const Color(0xFF16A34A);
    if (condition == ToothCondition.missing) textColor = Colors.black54;

    final textSpan = TextSpan(
      text: tid,
      style: TextStyle(
        color: textColor,
        fontSize: 10,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        decoration: isSelected ? TextDecoration.underline : null,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(data.labelX, data.labelY - 5));
  }

  @override
  bool shouldRepaint(covariant OdontogramPainter oldDelegate) {
    return true;
  }
}

import 'package:flutter/material.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/court_homography.dart';
import 'package:volleylive/presentation/providers/court_statistician_provider.dart';

class CourtHomographyOverlay extends StatelessWidget {
  final CourtStatisticianProvider provider;
  final ValueChanged<CourtZone>? onZoneTapped;

  const CourtHomographyOverlay({
    super.key,
    required this.provider,
    this.onZoneTapped,
  });

  @override
  Widget build(BuildContext context) {
    final zones = provider.engine.generateZones(provider.gridMode);
    final heatmap = provider.getZoneHeatmapIntensities();
    final netLine = provider.engine.getNetLine();
    final farAttackLine = provider.engine.getFarAttackLine();
    final nearAttackLine = provider.engine.getNearAttackLine();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Warstwa rysująca siatkę perspektywiczną całego boiska ze strefami obu stron
            CustomPaint(
              size: viewportSize,
              painter: _TwoSidedCourtPainter(
                zones: zones,
                selectedZoneId: provider.selectedZone?.id,
                gridMode: provider.gridMode,
                showHeatmap: provider.showHeatmap,
                heatmapIntensities: heatmap,
                showLabels: provider.showGridLabels,
                isAlgorithmActive: provider.calibrationMode == CalibrationMode.automaticAlgorithm && provider.isAlgorithmRunning,
                screenCorners: provider.screenCorners,
                netLine: netLine,
                farAttackLine: farAttackLine,
                nearAttackLine: nearAttackLine,
              ),
            ),

            // 2. Detekcja dotknięć w strefy
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final tapPos = details.localPosition;
                final zone = provider.engine.findZoneAtPoint(tapPos, provider.gridMode);
                if (zone != null) {
                  provider.selectZone(zone);
                  provider.recordCurrentStatEvent(targetZone: zone, tapOffset: tapPos);
                  onZoneTapped?.call(zone);
                }
              },
            ),

            // 3. Uchwyty do ręcznej kalibracji 4 narożników (P1..P4)
            if (provider.calibrationMode == CalibrationMode.manual)
              ...List.generate(provider.screenCorners.length, (index) {
                final corner = provider.screenCorners[index];

                return Positioned(
                  left: corner.dx - 22,
                  top: corner.dy - 22,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      provider.updateCorner(
                        index,
                        corner + details.delta,
                        clampBounds: viewportSize,
                      );
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.amberAccent.withValues(alpha: 0.92),
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                          ...AppTheme.cyanGlow(blur: 10, opacity: 0.4),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'P${index + 1}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _TwoSidedCourtPainter extends CustomPainter {
  final List<CourtZone> zones;
  final String? selectedZoneId;
  final ZoneGridMode gridMode;
  final bool showHeatmap;
  final Map<String, double> heatmapIntensities;
  final bool showLabels;
  final bool isAlgorithmActive;
  final List<Offset> screenCorners;
  final List<Offset> netLine;
  final List<Offset> farAttackLine;
  final List<Offset> nearAttackLine;

  _TwoSidedCourtPainter({
    required this.zones,
    required this.selectedZoneId,
    required this.gridMode,
    required this.showHeatmap,
    required this.heatmapIntensities,
    required this.showLabels,
    required this.isAlgorithmActive,
    required this.screenCorners,
    required this.netLine,
    required this.farAttackLine,
    required this.nearAttackLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // 1. RYSOWANIE STREF OBU STRON BOISKA
    for (final zone in zones) {
      final isSelected = zone.id == selectedZoneId;
      final path = Path()..addPolygon(zone.polygonPoints, true);
      final isNearSide = zone.side == CourtSide.near;

      // Kolorowanie strefy:
      final Paint fillPaint = Paint()..style = PaintingStyle.fill;

      if (showHeatmap && heatmapIntensities.containsKey(zone.id)) {
        final intensity = heatmapIntensities[zone.id] ?? 0.0;
        fillPaint.color = _getHeatmapColor(intensity);
      } else if (isSelected) {
        fillPaint.color = AppTheme.amberAccent.withValues(alpha: 0.55);
      } else {
        // Zróżnicowanie kolorystyczne stron boiska (Near vs Far)
        fillPaint.color = isNearSide
            ? _getNearZoneBaseColor(zone)
            : _getFarZoneBaseColor(zone);
      }

      canvas.drawPath(path, fillPaint);

      // Obrys strefy
      final Paint borderPaint = Paint()..style = PaintingStyle.stroke;
      if (isSelected) {
        borderPaint
          ..color = AppTheme.amberAccent
          ..strokeWidth = 3.0;
      } else if (gridMode == ZoneGridMode.zones36Subdivided) {
        borderPaint
          ..color = Colors.white.withValues(alpha: 0.25)
          ..strokeWidth = 0.8;
      } else {
        borderPaint
          ..color = isNearSide
              ? AppTheme.cyanAccent.withValues(alpha: 0.7)
              : Colors.purpleAccent.withValues(alpha: 0.7)
          ..strokeWidth = 1.6;
      }

      canvas.drawPath(path, borderPaint);

      // 2. ETYKIETY TEKSTOWE
      if (showLabels) {
        final double fontSize;
        if (gridMode == ZoneGridMode.zones36Subdivided) {
          fontSize = isNearSide ? 9.0 : 8.0;
        } else if (gridMode == ZoneGridMode.zones9) {
          fontSize = isNearSide ? 12.0 : 10.5;
        } else {
          fontSize = isNearSide ? 14.0 : 12.0;
        }

        final textColor = isSelected
            ? Colors.black
            : (isNearSide ? Colors.white : Colors.white.withValues(alpha: 0.9));

        textPainter.text = TextSpan(
          text: zone.label,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            shadows: isSelected
                ? null
                : const [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                  ],
          ),
        );
        textPainter.layout();
        final textPos = Offset(
          zone.centerPoint.dx - textPainter.width / 2,
          zone.centerPoint.dy - textPainter.height / 2,
        );
        textPainter.paint(canvas, textPos);
      }
    }

    // 3. LINIE BOISKA: LINIE 3m (LINIE ATAKU) DLA OBU STRON
    final attackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    if (farAttackLine.length == 2) {
      canvas.drawLine(farAttackLine[0], farAttackLine[1], attackPaint);
    }
    if (nearAttackLine.length == 2) {
      canvas.drawLine(nearAttackLine[0], nearAttackLine[1], attackPaint);
    }

    // 4. OBRYS CAŁEGO BOISKA (OUTER BOUNDARY)
    if (screenCorners.length == 4) {
      final outerPath = Path()..addPolygon(screenCorners, true);
      final outerPaint = Paint()
        ..color = isAlgorithmActive ? AppTheme.greenLive : AppTheme.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8;
      canvas.drawPath(outerPath, outerPaint);
    }

    // 5. SIATKA ŚRODKOWA (NET BAND & MESH)
    if (netLine.length == 2) {
      // Pas górny siatki (Biała taśma)
      final netBandPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 4.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(netLine[0], netLine[1], netBandPaint);

      // Obliczenie wektora prostopadłego do siatki
      final double dx = netLine[1].dx - netLine[0].dx;
      final double dy = netLine[1].dy - netLine[0].dy;
      final double invLen = 1.0 / (dx * dx + dy * dy > 0 ? (dx * dx + dy * dy) : 1.0);
      final double nx = -dy * invLen * 10;
      final double ny = dx * invLen * 10;

      // Cień siatki
      final netShadowPaint = Paint()
        ..color = Colors.black87
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(netLine[0].dx + nx * 0.3, netLine[0].dy + ny * 0.3),
        Offset(netLine[1].dx + nx * 0.3, netLine[1].dy + ny * 0.3),
        netShadowPaint,
      );

      // Antenki na krawędziach siatki (Lewa i Prawa antena prostopadle do siatki)
      final antennaPaintRed = Paint()..color = Colors.redAccent..strokeWidth = 3.5;
      canvas.drawLine(
        Offset(netLine[0].dx - nx * 1.5, netLine[0].dy - ny * 1.5),
        Offset(netLine[0].dx + nx * 1.5, netLine[0].dy + ny * 1.5),
        antennaPaintRed,
      );
      canvas.drawLine(
        Offset(netLine[1].dx - nx * 1.5, netLine[1].dy - ny * 1.5),
        Offset(netLine[1].dx + nx * 1.5, netLine[1].dy + ny * 1.5),
        antennaPaintRed,
      );

      // Napis NET w środku
      textPainter.text = const TextSpan(
        text: '── SIATKA (NET) ──',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      );
      textPainter.layout();
      final netCenter = Offset(
        (netLine[0].dx + netLine[1].dx) / 2 - textPainter.width / 2,
        (netLine[0].dy + netLine[1].dy) / 2 - textPainter.height / 2,
      );
      textPainter.paint(canvas, netCenter);
    }

    // 6. WSKAŹNIK KALIBRACJI AI / HUD
    if (isAlgorithmActive && screenCorners.length == 4) {
      final cornerTargetPaint = Paint()
        ..color = AppTheme.greenLive
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      for (final corner in screenCorners) {
        canvas.drawCircle(corner, 6, cornerTargetPaint);
      }
    }
  }

  Color _getNearZoneBaseColor(CourtZone zone) {
    if (gridMode == ZoneGridMode.zones6) {
      // Kolorowanie jak w diagramie użytkownika (Obrazek 1):
      // Front row: Zone 4 (Pomarańcz), Zone 3 (Róż), Zone 2 (Fiolet)
      // Back row: Zone 5 (Zieleń), Zone 6 (Cyjan), Zone 1 (Niebieski)
      switch (zone.mainZoneNumber) {
        case 4:
          return const Color(0xFFE65100).withValues(alpha: 0.35); // Pomarańcz
        case 3:
          return const Color(0xFFD81B60).withValues(alpha: 0.35); // Róż / Magenta
        case 2:
          return const Color(0xFF7E57C2).withValues(alpha: 0.35); // Fiolet
        case 5:
          return const Color(0xFF2E7D32).withValues(alpha: 0.35); // Ciemna zieleń
        case 6:
          return const Color(0xFF00838F).withValues(alpha: 0.35); // Morski / Teal
        case 1:
          return const Color(0xFF1565C0).withValues(alpha: 0.35); // Niebieski
        default:
          return Colors.blue.withValues(alpha: 0.20);
      }
    } else if (gridMode == ZoneGridMode.zones9) {
      // 9 stref serving target grid (Obrazek 2)
      switch (zone.mainZoneNumber) {
        case 1:
          return const Color(0xFFE91E63).withValues(alpha: 0.35); // Róż
        case 2:
          return const Color(0xFFD32F2F).withValues(alpha: 0.35); // Czerwień
        case 3:
          return const Color(0xFFF57C00).withValues(alpha: 0.35); // Pomarańcz
        case 4:
          return const Color(0xFF7B1FA2).withValues(alpha: 0.35); // Fiolet
        case 5:
          return const Color(0xFF388E3C).withValues(alpha: 0.35); // Zieleń
        case 6:
          return const Color(0xFF689F38).withValues(alpha: 0.35); // Jasna zieleń
        case 7:
          return const Color(0xFF1976D2).withValues(alpha: 0.35); // Niebieski
        case 8:
          return const Color(0xFF0097A7).withValues(alpha: 0.35); // Morski
        case 9:
          return const Color(0xFF00796B).withValues(alpha: 0.35); // Ciemny morski
        default:
          return Colors.cyan.withValues(alpha: 0.20);
      }
    }
    return Colors.cyan.withValues(alpha: 0.15);
  }

  Color _getFarZoneBaseColor(CourtZone zone) {
    // Połowa przeciwnika - stonowane odcienie z czytelnym podziałem
    if (gridMode == ZoneGridMode.zones6) {
      switch (zone.mainZoneNumber) {
        case 4:
          return const Color(0xFFE65100).withValues(alpha: 0.22);
        case 3:
          return const Color(0xFFD81B60).withValues(alpha: 0.22);
        case 2:
          return const Color(0xFF7E57C2).withValues(alpha: 0.22);
        case 5:
          return const Color(0xFF2E7D32).withValues(alpha: 0.22);
        case 6:
          return const Color(0xFF00838F).withValues(alpha: 0.22);
        case 1:
          return const Color(0xFF1565C0).withValues(alpha: 0.22);
        default:
          return Colors.deepPurple.withValues(alpha: 0.20);
      }
    }
    return const Color(0xFF3F51B5).withValues(alpha: 0.20);
  }

  Color _getHeatmapColor(double intensity) {
    if (intensity < 0.33) {
      return Colors.greenAccent.withValues(alpha: 0.45);
    } else if (intensity < 0.66) {
      return Colors.amberAccent.withValues(alpha: 0.60);
    } else {
      return Colors.redAccent.withValues(alpha: 0.75);
    }
  }

  @override
  bool shouldRepaint(covariant _TwoSidedCourtPainter oldDelegate) => true;
}

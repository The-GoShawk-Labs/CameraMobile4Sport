import 'package:flutter/material.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/court_homography.dart';
import 'package:volleylive/presentation/providers/court_statistician_provider.dart';

/// Interaktywna makieta boiska 2D (Tactical 2D Pitch) zoptymalizowana do szybkiego kodowania stref
class Tactical2DCourtView extends StatelessWidget {
  final CourtStatisticianProvider provider;
  final ValueChanged<CourtZone>? onZoneTapped;

  const Tactical2DCourtView({
    super.key,
    required this.provider,
    this.onZoneTapped,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        final double maxHeight = constraints.maxHeight;

        if (maxWidth <= 0 || maxHeight <= 0) {
          return const SizedBox();
        }

        final isSideline = provider.orientation.isSideline;

        // Proporcja boiska siatkarskiego to 18m x 9m (2 : 1)
        // W widoku z tyłu (0°/180°): wysokość = 2 * szerokość
        // W widoku z boku (90°/270°): szerokość = 2 * wysokość
        final double courtAspect = isSideline ? 2.0 : 0.5;

        double courtWidth;
        double courtHeight;

        if (maxWidth / maxHeight > courtAspect) {
          // Ograniczone przez wysokość
          courtHeight = maxHeight * 0.94;
          courtWidth = courtHeight * courtAspect;
        } else {
          // Ograniczone przez szerokość
          courtWidth = maxWidth * 0.94;
          courtHeight = courtWidth / courtAspect;
        }

        return Center(
          child: Container(
            width: courtWidth,
            height: courtHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1424),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.5), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Tło parkietu i linie boiska (siatka, 3m linie ataku)
                  CustomPaint(
                    painter: _TacticalCourtGridPainter(
                      orientation: provider.orientation,
                      showHeatmap: provider.showHeatmap,
                    ),
                  ),

                  // 2. Interaktywna siatka klikalnych stref
                  _buildInteractiveZonesGrid(courtWidth, courtHeight),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInteractiveZonesGrid(double width, double height) {
    final zones = provider.engine.generateZones(provider.gridMode);
    final heatmap = provider.getZoneHeatmapIntensities();

    return Stack(
      children: [
        ...zones.map((zone) {
          final isSelected = zone.id == provider.selectedZone?.id;
          final intensity = heatmap[zone.id] ?? 0.0;

          return Positioned.fill(
            child: CustomPaint(
              painter: _ZonePolygonPainter(
                zone: zone,
                isSelected: isSelected,
                showHeatmap: provider.showHeatmap,
                heatmapIntensity: intensity,
                showLabels: provider.showGridLabels,
                gridMode: provider.gridMode,
              ),
            ),
          );
        }),
        Positioned.fill(
          child: GestureDetector(
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
        ),
      ],
    );
  }
}

class _TacticalCourtGridPainter extends CustomPainter {
  final CourtOrientation orientation;
  final bool showHeatmap;

  _TacticalCourtGridPainter({
    required this.orientation,
    required this.showHeatmap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final courtPaint = Paint()
      ..color = const Color(0xFF16253B)
      ..style = PaintingStyle.fill;

    // Tło kortu
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), courtPaint);

    final attackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final netPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final isSideline = orientation.isSideline;

    if (isSideline) {
      // Widok z boku (poziomy)
      final midX = size.width / 2;

      // Linie ataku 3m
      canvas.drawLine(Offset(size.width * 2 / 6, 0), Offset(size.width * 2 / 6, size.height), attackPaint);
      canvas.drawLine(Offset(size.width * 4 / 6, 0), Offset(size.width * 4 / 6, size.height), attackPaint);

      // Siatka (pionowa linia w środku)
      canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), netPaint);
    } else {
      // Widok z tyłu (pionowy)
      final midY = size.height / 2;

      // Linie ataku 3m
      canvas.drawLine(Offset(0, size.height * 2 / 6), Offset(size.width, size.height * 2 / 6), attackPaint);
      canvas.drawLine(Offset(0, size.height * 4 / 6), Offset(size.width, size.height * 4 / 6), attackPaint);

      // Siatka (pozioma linia w środku)
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), netPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TacticalCourtGridPainter oldDelegate) =>
      oldDelegate.orientation != orientation || oldDelegate.showHeatmap != showHeatmap;
}

class _ZonePolygonPainter extends CustomPainter {
  final CourtZone zone;
  final bool isSelected;
  final bool showHeatmap;
  final double heatmapIntensity;
  final bool showLabels;
  final ZoneGridMode gridMode;

  _ZonePolygonPainter({
    required this.zone,
    required this.isSelected,
    required this.showHeatmap,
    required this.heatmapIntensity,
    required this.showLabels,
    required this.gridMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (zone.polygonPoints.isEmpty) return;

    final path = Path()..addPolygon(zone.polygonPoints, true);
    final isNearSide = zone.side == CourtSide.near;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    if (showHeatmap && heatmapIntensity > 0) {
      if (heatmapIntensity < 0.33) {
        fillPaint.color = Colors.greenAccent.withValues(alpha: 0.55);
      } else if (heatmapIntensity < 0.66) {
        fillPaint.color = Colors.amberAccent.withValues(alpha: 0.70);
      } else {
        fillPaint.color = Colors.redAccent.withValues(alpha: 0.85);
      }
    } else if (isSelected) {
      fillPaint.color = AppTheme.amberAccent.withValues(alpha: 0.6);
    } else {
      fillPaint.color = isNearSide
          ? _getNearColor(zone.mainZoneNumber)
          : _getFarColor(zone.mainZoneNumber);
    }

    canvas.drawPath(path, fillPaint);

    // Krawędź strefy
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = isSelected
          ? AppTheme.amberAccent
          : (isNearSide ? AppTheme.cyanAccent.withValues(alpha: 0.6) : Colors.purpleAccent.withValues(alpha: 0.6))
      ..strokeWidth = isSelected ? 2.5 : 1.0;

    canvas.drawPath(path, strokePaint);

    // Etykieta strefy
    if (showLabels) {
      final double fontSize = gridMode == ZoneGridMode.zones36Subdivided
          ? 8.5
          : (gridMode == ZoneGridMode.zones9 ? 11.5 : 14.0);

      final textPainter = TextPainter(
        text: TextSpan(
          text: zone.label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            shadows: isSelected
                ? null
                : const [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                  ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final textOffset = Offset(
        zone.centerPoint.dx - textPainter.width / 2,
        zone.centerPoint.dy - textPainter.height / 2,
      );

      textPainter.paint(canvas, textOffset);
    }
  }

  Color _getNearColor(int zoneNum) {
    switch (zoneNum) {
      case 4:
        return const Color(0xFFE65100).withValues(alpha: 0.35);
      case 3:
        return const Color(0xFFD81B60).withValues(alpha: 0.35);
      case 2:
        return const Color(0xFF7E57C2).withValues(alpha: 0.35);
      case 5:
        return const Color(0xFF2E7D32).withValues(alpha: 0.35);
      case 6:
        return const Color(0xFF00838F).withValues(alpha: 0.35);
      case 1:
        return const Color(0xFF1565C0).withValues(alpha: 0.35);
      default:
        return AppTheme.cyanAccent.withValues(alpha: 0.25);
    }
  }

  Color _getFarColor(int zoneNum) {
    switch (zoneNum) {
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
        return Colors.deepPurpleAccent.withValues(alpha: 0.20);
    }
  }

  @override
  bool shouldRepaint(covariant _ZonePolygonPainter oldDelegate) => true;
}

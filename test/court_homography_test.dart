import 'package:flutter_test/flutter_test.dart';
import 'package:volleylive/domain/models/court_homography.dart';

void main() {
  group('HomographyEngine Two-Sided Court Tests', () {
    late HomographyEngine engine;

    setUp(() {
      engine = HomographyEngine(
        screenCorners: [
          const Offset(100, 100), // Far-Left
          const Offset(500, 100), // Far-Right
          const Offset(550, 400), // Near-Right
          const Offset(50, 400),  // Near-Left
        ],
      );
    });

    test('Generates 12 zones for basic 6-zone mode (6 per side)', () {
      final zones = engine.generateZones(ZoneGridMode.zones6);
      expect(zones.length, equals(12));
      
      final nearZones = zones.where((z) => z.side == CourtSide.near).toList();
      final farZones = zones.where((z) => z.side == CourtSide.far).toList();

      expect(nearZones.length, equals(6));
      expect(farZones.length, equals(6));

      // Sprawdzenie obecności stref 1-6 na obu stronach
      for (int i = 1; i <= 6; i++) {
        expect(nearZones.any((z) => z.mainZoneNumber == i), isTrue);
        expect(farZones.any((z) => z.mainZoneNumber == i), isTrue);
      }

      // Strefa 4 na stronie bliższej (Near) powinna być przy siatce po lewej stronie
      final nearZ4 = nearZones.firstWhere((z) => z.mainZoneNumber == 4);
      expect(nearZ4.id, equals('A_Z4'));
      expect(nearZ4.label, equals('A4'));
    });

    test('Generates 18 target zones for 9-zone mode (9 per side)', () {
      final zones = engine.generateZones(ZoneGridMode.zones9);
      expect(zones.length, equals(18));

      final nearZones = zones.where((z) => z.side == CourtSide.near).toList();
      final farZones = zones.where((z) => z.side == CourtSide.far).toList();

      expect(nearZones.length, equals(9));
      expect(farZones.length, equals(9));

      // Sprawdzenie celów 1..9
      for (int i = 1; i <= 9; i++) {
        expect(nearZones.any((z) => z.mainZoneNumber == i), isTrue);
        expect(farZones.any((z) => z.mainZoneNumber == i), isTrue);
      }
    });

    test('Generates 72 subdivided zones for max extended mode (36 per side - 9 zones x 4)', () {
      final zones = engine.generateZones(ZoneGridMode.zones36Subdivided);
      expect(zones.length, equals(72));

      final nearZones = zones.where((z) => z.side == CourtSide.near).toList();
      final farZones = zones.where((z) => z.side == CourtSide.far).toList();

      expect(nearZones.length, equals(36));
      expect(farZones.length, equals(36));

      expect(nearZones.where((z) => z.mainZoneNumber == 1).length, equals(4));
    });

    test('Sideline 90-degree camera orientation generates correct vertical net and 12 zones', () {
      final sideEngine = HomographyEngine(
        screenCorners: [
          const Offset(50, 100),
          const Offset(550, 100),
          const Offset(550, 400),
          const Offset(50, 400),
        ],
        orientation: CourtOrientation.sidelineLeftToRight,
      );

      final zones = sideEngine.generateZones(ZoneGridMode.zones6);
      expect(zones.length, equals(12));

      final netLine = sideEngine.getNetLine();
      expect(netLine.length, equals(2));
      // W widoku z boku (90° L->P) siatka jest w pionowym centrum (dx blisko 300)
      expect((netLine[0].dx - netLine[1].dx).abs(), lessThan(1.0));
      expect((netLine[0].dy - netLine[1].dy).abs(), greaterThan(100.0));
    });

    test('All orientations support next cyclic rotation', () {
      expect(CourtOrientation.endlineNearBottom.next, equals(CourtOrientation.sidelineLeftToRight));
      expect(CourtOrientation.sidelineLeftToRight.next, equals(CourtOrientation.endlineNearTop));
      expect(CourtOrientation.endlineNearTop.next, equals(CourtOrientation.sidelineRightToLeft));
      expect(CourtOrientation.sidelineRightToLeft.next, equals(CourtOrientation.endlineNearBottom));
    });
  });
}

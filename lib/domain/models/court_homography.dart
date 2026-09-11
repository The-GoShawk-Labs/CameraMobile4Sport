import 'dart:ui';

/// Orientacja kamery / widok boiska
enum CourtOrientation {
  /// Kamera z tyłu boiska (standardowy widok wzdłużny, siatka pozioma, nasza strona na dole)
  endlineNearBottom(
    degrees: 0,
    label: 'Z tyłu boiska (Dół ➔ Góra)',
    shortLabel: '0° Z tyłu',
    isSideline: false,
  ),

  /// Kamera z boku boiska (widok poprzeczny, siatka pionowa, strona A po lewej, strona B po prawej)
  sidelineLeftToRight(
    degrees: 90,
    label: 'Z boku boiska (Lewo ➔ Prawo)',
    shortLabel: '90° Z boku (L➔P)',
    isSideline: true,
  ),

  /// Kamera z tyłu z przeciwległego końca (siatka pozioma, nasza strona na górze)
  endlineNearTop(
    degrees: 180,
    label: 'Z tyłu boiska (Góra ➔ Dół)',
    shortLabel: '180° Z tyłu (Odwrócone)',
    isSideline: false,
  ),

  /// Kamera z drugiego boku boiska (siatka pionowa, strona B po lewej, strona A po prawej)
  sidelineRightToLeft(
    degrees: 270,
    label: 'Z boku boiska (Prawo ➔ Lewo)',
    shortLabel: '270° Z boku (P➔L)',
    isSideline: true,
  );

  final int degrees;
  final String label;
  final String shortLabel;
  final bool isSideline;

  const CourtOrientation({
    required this.degrees,
    required this.label,
    required this.shortLabel,
    required this.isSideline,
  });

  /// Następna orientacja (obrót o 90 stopni zgodnie z ruchem wskazówek zegara)
  CourtOrientation get next {
    switch (this) {
      case CourtOrientation.endlineNearBottom:
        return CourtOrientation.sidelineLeftToRight;
      case CourtOrientation.sidelineLeftToRight:
        return CourtOrientation.endlineNearTop;
      case CourtOrientation.endlineNearTop:
        return CourtOrientation.sidelineRightToLeft;
      case CourtOrientation.sidelineRightToLeft:
        return CourtOrientation.endlineNearBottom;
    }
  }
}

/// Strona boiska
enum CourtSide {
  near('Nasza / Bliższa (A)', 'A'),
  far('Przeciwnik / Dalsza (B)', 'B');

  final String displayName;
  final String code;
  const CourtSide(this.displayName, this.code);
}

/// Tryb podziału stref boiska (wartości per połowa oraz suma na całe boisko)
enum ZoneGridMode {
  /// Podstawowy: 6 stref na stronę (łącznie 12 stref na całym boisku)
  /// Układ zgodny z rotacją FIVB: Linia ataku 3m + linia obrony 6m
  zones6(
    zonesPerSide: 6,
    totalZones: 12,
    title: '6 stref / stronę (12 łącznie)',
    description: 'Klasyczny podział siatkarski: Strefy 1-6 (rotacja, atak/obrona)',
  ),

  /// Rozszerzony: 9 stref na stronę (łącznie 18 stref na całym boisku)
  /// Układ siatki 3x3 per połowa (Short, Middle, Deep)
  zones9(
    zonesPerSide: 9,
    totalZones: 18,
    title: '9 stref / stronę (18 łącznie)',
    description: 'Siatka celów 3x3: Krótka (1-3), Średnia (4-6), Długa (7-9)',
  ),

  /// Najbardziej rozszerzony: 36 podstref na stronę (łącznie 72 podstrefy na całym boisku)
  /// Każda z 9 stref podzielona na 4 sektory 2x2 (A, B, C, D)
  zones36Subdivided(
    zonesPerSide: 36,
    totalZones: 72,
    title: '36 podstref / stronę (72 łącznie)',
    description: 'Precyzyjna siatka DataVolley/FIVB: 9 stref x 4 podstrefy (A, B, C, D)',
  );

  final int zonesPerSide;
  final int totalZones;
  final String title;
  final String description;

  const ZoneGridMode({
    required this.zonesPerSide,
    required this.totalZones,
    required this.title,
    required this.description,
  });
}

/// Tryb wyświetlania makiety boiska dla statystyka
enum CourtDisplayMode {
  tactical2D(
    title: 'Makieta Taktyczna 2D',
    shortLabel: '2D Taktyczna',
    description: 'Płaski, wyrazisty rzut z góry zoptymalizowany pod szybkie stukanie kciukiem.',
  ),
  cameraPerspective(
    title: 'Kamera Statywowa (Perspektywa)',
    shortLabel: 'Perspektywa',
    description: 'Rzut perspektywiczny z nakładką homograficzną bezpośrednio na kadr wideo.',
  );

  final String title;
  final String shortLabel;
  final String description;

  const CourtDisplayMode({
    required this.title,
    required this.shortLabel,
    required this.description,
  });
}

/// Rozmiar pływającego okna odtwarzacza PiP
enum PipSizeState {
  normal(width: 260, height: 160),
  expanded(width: 340, height: 210),
  miniPill(width: 180, height: 48);

  final double width;
  final double height;

  const PipSizeState({
    required this.width,
    required this.height,
  });
}

/// Tryb kalibracji perspektywy / homografii
enum CalibrationMode {
  manual,
  automaticAlgorithm,
}

/// Dostępne algorytmy detekcji geometrii boiska
enum HomographyAlgorithm {
  houghLines(
    id: 'hough_lines',
    name: 'OpenCV Hough Line / Court Edge',
    description: 'Klasyczna detekcja krawędzi i linii boiska metodą transformaty Hougha.',
    typicalAccuracy: 0.92,
  ),
  deepKeypoints(
    id: 'deep_keypoints',
    name: 'CourtNet Keypoint ML (Live)',
    description: 'Głęboka sieć neuronowa wykrywająca narożniki i punkty charakterystyczne.',
    typicalAccuracy: 0.97,
  ),
  opticalFlowStabilizer(
    id: 'optical_flow',
    name: 'Optical Flow & Homography Tracker',
    description: 'Stabilizacja i ciągłe śledzenie geometrii statycznej kamery z kompensacją mikrodrgań.',
    typicalAccuracy: 0.95,
  );

  final String id;
  final String name;
  final String description;
  final double typicalAccuracy;

  const HomographyAlgorithm({
    required this.id,
    required this.name,
    required this.description,
    required this.typicalAccuracy,
  });
}

/// Pojedyncza strefa boiska w rzucie perspektywicznym
class CourtZone {
  final String id; // np. 'A_Z1', 'B_Z4', 'A_9D'
  final String label; // np. 'A1', 'BT4', 'A9D'
  final String fullDisplayLabel; // np. 'Drużyna A - Strefa 1 (Prawy tył)'
  final CourtSide side;
  final int mainZoneNumber;
  final String? subZoneLetter;
  final String roleDescription; // np. 'Prawa linia ataku', 'Środek obrony'
  final List<Offset> polygonPoints; // 4 punkty na ekranie (TL, TR, BR, BL)
  final Offset centerPoint;

  const CourtZone({
    required this.id,
    required this.label,
    required this.fullDisplayLabel,
    required this.side,
    required this.mainZoneNumber,
    this.subZoneLetter,
    required this.roleDescription,
    required this.polygonPoints,
    required this.centerPoint,
  });
}

/// Model zarejestrowanego zdarzenia statystycznego
class StatEvent {
  final String id;
  final DateTime timestamp;
  final String actionType; // 'ZAGRYWKA', 'ATAK', 'PRZYJĘCIE', 'BLOK', 'OBRONA'
  final String qualityGrade; // '#', '+', '!', '-', '/'
  final String teamName;
  final CourtZone zone;
  final Offset tapLocation;

  const StatEvent({
    required this.id,
    required this.timestamp,
    required this.actionType,
    required this.qualityGrade,
    required this.teamName,
    required this.zone,
    required this.tapLocation,
  });
}

/// Silnik matematyczny homografii i rzutowania perspektywicznego całego boiska siatkarskiego
class HomographyEngine {
  /// 4 narożniki czworokąta boiska na ekranie kamery:
  /// [0] = Narożnik 1 (Top-Left kadru)
  /// [1] = Narożnik 2 (Top-Right kadru)
  /// [2] = Narożnik 3 (Bottom-Right kadru)
  /// [3] = Narożnik 4 (Bottom-Left kadru)
  final List<Offset> screenCorners;

  /// Orientacja kamery względem boiska
  final CourtOrientation orientation;

  HomographyEngine({
    required this.screenCorners,
    this.orientation = CourtOrientation.endlineNearBottom,
  }) {
    assert(screenCorners.length == 4, 'Wymagane są dokładnie 4 punkty narożne boiska.');
  }

  /// Dwuliniowe przekształcenie perspektywiczne punktu znormalizowanego ekranu (u, v) in [0, 1]^2 na piksele ekranu
  Offset transformScreenNormPoint(double u, double v) {
    final top = Offset.lerp(screenCorners[0], screenCorners[1], u)!;
    final bottom = Offset.lerp(screenCorners[3], screenCorners[2], u)!;
    return Offset.lerp(top, bottom, v)!;
  }

  /// Przekształcenie punktu współrzędnych boiska (xc, yc) in [0, 1]^2 na piksele ekranu
  /// xc in [0, 1] = lewa linia boczna (0) do prawej linii bocznej (1)
  /// yc in [0, 1] = dalsza linia końcowa (0) do siatki (0.5) do bliższej linii końcowej (1)
  Offset transformCourtPoint(double xc, double yc) {
    final screenNorm = mapCourtToScreenNorm(xc, yc, orientation);
    return transformScreenNormPoint(screenNorm.dx, screenNorm.dy);
  }

  /// Mapowanie współrzędnych boiska (xc, yc) na znormalizowane współrzędne ekranowe (u, v) wg orientacji
  static Offset mapCourtToScreenNorm(double xc, double yc, CourtOrientation orient) {
    switch (orient) {
      case CourtOrientation.endlineNearBottom:
        // 0° - Widok z tyłu: Near (yc=1) na dole (v=1), Far (yc=0) na górze (v=0)
        return Offset(xc, yc);

      case CourtOrientation.sidelineLeftToRight:
        // 90° - Widok z boku: Near (yc=1) po lewej (u=0), Net (yc=0.5) w środku (u=0.5), Far (yc=0) po prawej (u=1)
        // Lewa linia boczna (xc=0) na górze (v=0), Prawa linia boczna (xc=1) na dole (v=1)
        return Offset(1.0 - yc, xc);

      case CourtOrientation.endlineNearTop:
        // 180° - Widok z tyłu odwrócony: Near (yc=1) na górze (v=0), Far (yc=0) na dole (v=1)
        return Offset(1.0 - xc, 1.0 - yc);

      case CourtOrientation.sidelineRightToLeft:
        // 270° - Widok z boku (z przeciwnego boku): Far (yc=0) po lewej (u=0), Near (yc=1) po prawej (u=1)
        return Offset(yc, 1.0 - xc);
    }
  }

  /// Pobranie linii siatki na ekranie
  List<Offset> getNetLine() {
    return [
      transformCourtPoint(0.0, 0.5),
      transformCourtPoint(1.0, 0.5),
    ];
  }

  /// Pobranie linii ataku 3m (dla obu stron: dalszej yc=0.3333 i bliższej yc=0.6667)
  List<Offset> getFarAttackLine() {
    return [
      transformCourtPoint(0.0, 1.0 / 3.0),
      transformCourtPoint(1.0, 1.0 / 3.0),
    ];
  }

  List<Offset> getNearAttackLine() {
    return [
      transformCourtPoint(0.0, 2.0 / 3.0),
      transformCourtPoint(1.0, 2.0 / 3.0),
    ];
  }

  /// Generowanie wszystkich stref dla OBU stron boiska (pełne boisko)
  List<CourtZone> generateZones(ZoneGridMode mode) {
    final List<CourtZone> zones = [];

    switch (mode) {
      case ZoneGridMode.zones6:
        zones.addAll(_generate6ZonesForSide(CourtSide.near));
        zones.addAll(_generate6ZonesForSide(CourtSide.far));
        break;

      case ZoneGridMode.zones9:
        zones.addAll(_generate9ZonesForSide(CourtSide.near));
        zones.addAll(_generate9ZonesForSide(CourtSide.far));
        break;

      case ZoneGridMode.zones36Subdivided:
        zones.addAll(_generate36SubdividedZonesForSide(CourtSide.near));
        zones.addAll(_generate36SubdividedZonesForSide(CourtSide.far));
        break;
    }

    return zones;
  }

  List<CourtZone> _generate6ZonesForSide(CourtSide side) {
    final List<CourtZone> zones = [];
    final bool isNear = side == CourtSide.near;

    final List<_Zone6Def> defs;

    if (isNear) {
      // Strona bliższa (Near / A)
      defs = [
        // Front row (przy siatce)
        _Zone6Def(4, 0.0 / 3.0, 1.0 / 3.0, 0.50, 2.0 / 3.0, 'Lewy przód (Atak lewe skrzydło)'),
        _Zone6Def(3, 1.0 / 3.0, 2.0 / 3.0, 0.50, 2.0 / 3.0, 'Środek przód (Atak ze środka)'),
        _Zone6Def(2, 2.0 / 3.0, 3.0 / 3.0, 0.50, 2.0 / 3.0, 'Prawy przód (Rozegranie / Prawa)'),
        // Back row (druga linia)
        _Zone6Def(5, 0.0 / 3.0, 1.0 / 3.0, 2.0 / 3.0, 1.00, 'Lewy tył (Obrona lewe skrzydło)'),
        _Zone6Def(6, 1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1.00, 'Środek tył (Głęboka obrona)'),
        _Zone6Def(1, 2.0 / 3.0, 3.0 / 3.0, 2.0 / 3.0, 1.00, 'Prawy tył (Strefa zagrywki)'),
      ];
    } else {
      // Strona dalsza (Far / B)
      defs = [
        _Zone6Def(2, 0.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 0.50, 'Prawy przód przeciwnika'),
        _Zone6Def(3, 1.0 / 3.0, 2.0 / 3.0, 1.0 / 3.0, 0.50, 'Środek przód przeciwnika'),
        _Zone6Def(4, 2.0 / 3.0, 3.0 / 3.0, 1.0 / 3.0, 0.50, 'Lewy przód przeciwnika'),
        _Zone6Def(1, 0.0 / 3.0, 1.0 / 3.0, 0.00, 1.0 / 3.0, 'Prawy tył przeciwnika (Zagrywka)'),
        _Zone6Def(6, 1.0 / 3.0, 2.0 / 3.0, 0.00, 1.0 / 3.0, 'Środek tył przeciwnika'),
        _Zone6Def(5, 2.0 / 3.0, 3.0 / 3.0, 0.00, 1.0 / 3.0, 'Lewy tył przeciwnika'),
      ];
    }

    for (final def in defs) {
      final pTL = transformCourtPoint(def.uStart, def.vStart);
      final pTR = transformCourtPoint(def.uEnd, def.vStart);
      final pBR = transformCourtPoint(def.uEnd, def.vEnd);
      final pBL = transformCourtPoint(def.uStart, def.vEnd);
      final center = transformCourtPoint((def.uStart + def.uEnd) / 2, (def.vStart + def.vEnd) / 2);

      final sidePrefix = side.code;
      zones.add(CourtZone(
        id: '${sidePrefix}_Z${def.num}',
        label: '$sidePrefix${def.num}',
        fullDisplayLabel: '${side.displayName}: Strefa ${def.num}',
        side: side,
        mainZoneNumber: def.num,
        roleDescription: def.role,
        polygonPoints: [pTL, pTR, pBR, pBL],
        centerPoint: center,
      ));
    }

    return zones;
  }

  List<CourtZone> _generate9ZonesForSide(CourtSide side) {
    final List<CourtZone> zones = [];
    final bool isNear = side == CourtSide.near;

    final double vBase = isNear ? 0.50 : 0.00;
    final double vHeight = 0.50 / 3.0;

    for (int r = 0; r < 3; r++) {
      final double v1;
      final double v2;
      final String depthName;

      if (isNear) {
        v1 = vBase + (r * vHeight);
        v2 = vBase + ((r + 1) * vHeight);
        depthName = r == 0 ? 'Krótka (Short)' : (r == 1 ? 'Średnia (Middle)' : 'Głęboka (Deep)');
      } else {
        final invR = 2 - r;
        v1 = vBase + (invR * vHeight);
        v2 = vBase + ((invR + 1) * vHeight);
        depthName = r == 0 ? 'Krótka (Short)' : (r == 1 ? 'Średnia (Middle)' : 'Głęboka (Deep)');
      }

      for (int c = 0; c < 3; c++) {
        final double u1 = c / 3.0;
        final double u2 = (c + 1) / 3.0;

        final int targetNum;
        final String colName;

        if (isNear) {
          final targetCol = (3 - c);
          targetNum = r * 3 + targetCol;
          colName = c == 0 ? 'Lewa' : (c == 1 ? 'Środek' : 'Prawa');
        } else {
          final targetCol = c + 1;
          targetNum = r * 3 + targetCol;
          colName = c == 0 ? 'Prawa przeciwnika' : (c == 1 ? 'Środek' : 'Lewa przeciwnika');
        }

        final pTL = transformCourtPoint(u1, v1);
        final pTR = transformCourtPoint(u2, v1);
        final pBR = transformCourtPoint(u2, v2);
        final pBL = transformCourtPoint(u1, v2);
        final center = transformCourtPoint((u1 + u2) / 2, (v1 + v2) / 2);

        final sidePrefix = side.code;
        zones.add(CourtZone(
          id: '${sidePrefix}_T$targetNum',
          label: '$sidePrefix$targetNum',
          fullDisplayLabel: '${side.displayName}: Cel $targetNum ($depthName $colName)',
          side: side,
          mainZoneNumber: targetNum,
          roleDescription: '$depthName $colName',
          polygonPoints: [pTL, pTR, pBR, pBL],
          centerPoint: center,
        ));
      }
    }

    return zones;
  }

  List<CourtZone> _generate36SubdividedZonesForSide(CourtSide side) {
    final List<CourtZone> zones = [];
    final base9Zones = _generate9ZonesForSide(side);
    const subLetters = ['A', 'B', 'C', 'D'];

    for (final baseZone in base9Zones) {
      final pTL = baseZone.polygonPoints[0];
      final pTR = baseZone.polygonPoints[1];
      final pBR = baseZone.polygonPoints[2];
      final pBL = baseZone.polygonPoints[3];

      for (int subR = 0; subR < 2; subR++) {
        for (int subC = 0; subC < 2; subC++) {
          final int subIdx = subR * 2 + subC;
          final String letter = subLetters[subIdx];

          final double u1 = subC * 0.5;
          final double u2 = (subC + 1) * 0.5;
          final double v1 = subR * 0.5;
          final double v2 = (subR + 1) * 0.5;

          final subTL = _bilinearLerp(pTL, pTR, pBR, pBL, u1, v1);
          final subTR = _bilinearLerp(pTL, pTR, pBR, pBL, u2, v1);
          final subBR = _bilinearLerp(pTL, pTR, pBR, pBL, u2, v2);
          final subBL = _bilinearLerp(pTL, pTR, pBR, pBL, u1, v2);
          final subCenter = _bilinearLerp(pTL, pTR, pBR, pBL, (u1 + u2) / 2, (v1 + v2) / 2);

          final sidePrefix = side.code;
          zones.add(CourtZone(
            id: '${sidePrefix}_${baseZone.mainZoneNumber}$letter',
            label: '$sidePrefix${baseZone.mainZoneNumber}$letter',
            fullDisplayLabel: '${side.displayName}: Podstrefa ${baseZone.mainZoneNumber}$letter',
            side: side,
            mainZoneNumber: baseZone.mainZoneNumber,
            subZoneLetter: letter,
            roleDescription: '${baseZone.roleDescription} (Sektor $letter)',
            polygonPoints: [subTL, subTR, subBR, subBL],
            centerPoint: subCenter,
          ));
        }
      }
    }

    return zones;
  }

  Offset _bilinearLerp(Offset tl, Offset tr, Offset br, Offset bl, double u, double v) {
    final top = Offset.lerp(tl, tr, u)!;
    final bottom = Offset.lerp(bl, br, u)!;
    return Offset.lerp(top, bottom, v)!;
  }

  /// Wykrywanie czy dany punkt dotknięcia znajduje się w wielokącie (Ray Casting Algorithm)
  static bool isPointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy)) &&
          (point.dx < (polygon[j].dx - polygon[i].dx) * (point.dy - polygon[i].dy) / (polygon[j].dy - polygon[i].dy) + polygon[i].dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Znalezienie strefy zawierającej dany punkt
  CourtZone? findZoneAtPoint(Offset point, ZoneGridMode mode) {
    final zones = generateZones(mode);
    for (final zone in zones) {
      if (isPointInPolygon(point, zone.polygonPoints)) {
        return zone;
      }
    }
    return null;
  }
}

class _Zone6Def {
  final int num;
  final double uStart;
  final double uEnd;
  final double vStart;
  final double vEnd;
  final String role;

  _Zone6Def(this.num, this.uStart, this.uEnd, this.vStart, this.vEnd, this.role);
}

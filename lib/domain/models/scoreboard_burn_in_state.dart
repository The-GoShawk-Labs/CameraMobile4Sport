import 'package:flutter/widgets.dart';
import 'package:volleylive/domain/models/match_recording_metadata.dart';
import 'package:volleylive/domain/models/match_session.dart';

/// Siatka 6 pozycji kotwiczenia tablicy wyników wewnątrz aktywnego kadru meczu.
enum ScoreboardAnchorPosition {
  topLeft,
  topCenter,
  topRight,
  bottomLeft,
  bottomCenter,
  bottomRight;

  static const double safeMarginX =
      0.025; // Broadcast Safe Margin X: 2.5% szerokości wideo
  static const double safeMarginY =
      0.035; // Broadcast Safe Margin Y: 3.5% wysokości wideo

  Alignment get alignment {
    switch (this) {
      case ScoreboardAnchorPosition.topLeft:
        return const Alignment(
          -1.0 + (2.0 * safeMarginX),
          -1.0 + (2.0 * safeMarginY),
        );
      case ScoreboardAnchorPosition.topCenter:
        return const Alignment(0.0, -1.0 + (2.0 * safeMarginY));
      case ScoreboardAnchorPosition.topRight:
        return const Alignment(
          1.0 - (2.0 * safeMarginX),
          -1.0 + (2.0 * safeMarginY),
        );
      case ScoreboardAnchorPosition.bottomLeft:
        return const Alignment(
          -1.0 + (2.0 * safeMarginX),
          1.0 - (2.0 * safeMarginY),
        );
      case ScoreboardAnchorPosition.bottomCenter:
        return const Alignment(0.0, 1.0 - (2.0 * safeMarginY));
      case ScoreboardAnchorPosition.bottomRight:
        return const Alignment(
          1.0 - (2.0 * safeMarginX),
          1.0 - (2.0 * safeMarginY),
        );
    }
  }

  /// Zwraca znormalizowane współrzędne (normX, normY) lewego górnego rogu tablicy w przestrzeni kadru [0.0, 1.0]
  ({double normX, double normY}) getNormalizedTopLeft({
    required double widgetWidthNorm,
    required double widgetHeightNorm,
  }) {
    double x;
    double y;
    switch (this) {
      case ScoreboardAnchorPosition.topLeft:
        x = safeMarginX;
        y = safeMarginY;
        break;
      case ScoreboardAnchorPosition.topCenter:
        x = (1.0 - widgetWidthNorm) / 2.0;
        y = safeMarginY;
        break;
      case ScoreboardAnchorPosition.topRight:
        x = 1.0 - safeMarginX - widgetWidthNorm;
        y = safeMarginY;
        break;
      case ScoreboardAnchorPosition.bottomLeft:
        x = safeMarginX;
        y = 1.0 - safeMarginY - widgetHeightNorm;
        break;
      case ScoreboardAnchorPosition.bottomCenter:
        x = (1.0 - widgetWidthNorm) / 2.0;
        y = 1.0 - safeMarginY - widgetHeightNorm;
        break;
      case ScoreboardAnchorPosition.bottomRight:
        x = 1.0 - safeMarginX - widgetWidthNorm;
        y = 1.0 - safeMarginY - widgetHeightNorm;
        break;
    }
    return (normX: x, normY: y);
  }

  String get label {
    switch (this) {
      case ScoreboardAnchorPosition.topLeft:
        return 'Góra Lewa';
      case ScoreboardAnchorPosition.topCenter:
        return 'Góra Środek';
      case ScoreboardAnchorPosition.topRight:
        return 'Góra Prawa';
      case ScoreboardAnchorPosition.bottomLeft:
        return 'Dół Lewa';
      case ScoreboardAnchorPosition.bottomCenter:
        return 'Dół Środek';
      case ScoreboardAnchorPosition.bottomRight:
        return 'Dół Prawa';
    }
  }

  static ScoreboardAnchorPosition fromName(String? name) {
    if (name == null) return ScoreboardAnchorPosition.topLeft;
    return ScoreboardAnchorPosition.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ScoreboardAnchorPosition.topLeft,
    );
  }
}

/// Representation of the dynamic volleyball scoreboard state sent to native
/// video processors (StreamPack on Android / HaishinKit on iOS) for frame burn-in.
@immutable
class VolleyballScoreboardState {
  final String teamA;
  final String teamB;
  final int scoreA;
  final int scoreB;
  final int currentSet;
  final int setsA;
  final int setsB;
  final String servingTeam; // "A", "B", or "NONE"
  final String? eventTag; // e.g. "ACE!", "BLOCK!", "TIMEOUT"
  final String? toastMessage;
  final ScoreboardAnchorPosition anchorPosition;
  final String matchClock;
  final int? colorA;
  final int? colorB;
  final String? teamAShort;
  final String? teamBShort;
  final bool useShortNames;

  const VolleyballScoreboardState({
    required this.teamA,
    required this.teamB,
    required this.scoreA,
    required this.scoreB,
    required this.currentSet,
    required this.setsA,
    required this.setsB,
    this.servingTeam = 'NONE',
    this.eventTag,
    this.toastMessage,
    this.anchorPosition = ScoreboardAnchorPosition.topLeft,
    this.matchClock = '',
    this.colorA,
    this.colorB,
    this.teamAShort,
    this.teamBShort,
    this.useShortNames = false,
  });

  /// Factory creating state directly from the app's [MatchSession]
  factory VolleyballScoreboardState.fromMatchSession(
    MatchSession session, {
    String? eventTag,
    String? toastMessage,
    ScoreboardAnchorPosition anchorPosition = ScoreboardAnchorPosition.topLeft,
    String matchClock = '',
    bool useShortNames = false,
  }) {
    String serverStr = 'NONE';
    if (session.currentServer == ServingTeam.teamA) {
      serverStr = 'A';
    } else if (session.currentServer == ServingTeam.teamB) {
      serverStr = 'B';
    }

    final rawToast = toastMessage ?? eventTag;
    final effectiveToast =
        ScoreTimelineEntry.isDisplayableSpecialBanner(rawToast)
        ? rawToast
        : null;

    return VolleyballScoreboardState(
      teamA: session.teamA.toUpperCase(),
      teamB: session.teamB.toUpperCase(),
      scoreA: session.currentSetPointsA,
      scoreB: session.currentSetPointsB,
      currentSet: session.currentSetNumber,
      setsA: session.setsA,
      setsB: session.setsB,
      servingTeam: serverStr,
      eventTag: effectiveToast,
      toastMessage: effectiveToast,
      anchorPosition: anchorPosition,
      matchClock: matchClock,
      colorA: session.teamAColor.toARGB32(),
      colorB: session.teamBColor.toARGB32(),
      teamAShort: session.teamAShortCode,
      teamBShort: session.teamBShortCode,
      useShortNames: useShortNames,
    );
  }

  Map<String, dynamic> toMap() => {
    'teamA': teamA,
    'teamB': teamB,
    'teamAName': teamA,
    'teamBName': teamB,
    'teamAShort': teamAShort ?? '',
    'teamBShort': teamBShort ?? '',
    'useShortNames': useShortNames,
    'scoreA': scoreA,
    'scoreB': scoreB,
    'currentSet': currentSet,
    'setsA': setsA,
    'setsB': setsB,
    'servingTeam': servingTeam,
    'eventTag': eventTag ?? toastMessage ?? '',
    'toastMessage': toastMessage ?? eventTag ?? '',
    'anchorPosition': anchorPosition.name,
    'matchClock': matchClock,
    if (colorA != null) 'colorA': colorA,
    if (colorB != null) 'colorB': colorB,
  };

  factory VolleyballScoreboardState.fromMap(Map<String, dynamic> map) {
    ScoreboardAnchorPosition anchor = ScoreboardAnchorPosition.topLeft;
    final anchorStr = map['anchorPosition'] as String?;
    if (anchorStr != null) {
      for (final p in ScoreboardAnchorPosition.values) {
        if (p.name == anchorStr) {
          anchor = p;
          break;
        }
      }
    }

    return VolleyballScoreboardState(
      teamA: map['teamA'] as String? ?? (map['teamAName'] as String? ?? 'DRUŻYNA A'),
      teamB: map['teamB'] as String? ?? (map['teamBName'] as String? ?? 'DRUŻYNA B'),
      scoreA: map['scoreA'] as int? ?? 0,
      scoreB: map['scoreB'] as int? ?? 0,
      currentSet: map['currentSet'] as int? ?? 1,
      setsA: map['setsA'] as int? ?? 0,
      setsB: map['setsB'] as int? ?? 0,
      servingTeam: map['servingTeam'] as String? ?? 'NONE',
      eventTag: (map['eventTag'] as String?)?.isNotEmpty == true ? map['eventTag'] as String : null,
      toastMessage: (map['toastMessage'] as String?)?.isNotEmpty == true ? map['toastMessage'] as String : null,
      anchorPosition: anchor,
      matchClock: map['matchClock'] as String? ?? '',
      colorA: map['colorA'] as int?,
      colorB: map['colorB'] as int?,
      teamAShort: (map['teamAShort'] as String?)?.isNotEmpty == true ? map['teamAShort'] as String : null,
      teamBShort: (map['teamBShort'] as String?)?.isNotEmpty == true ? map['teamBShort'] as String : null,
      useShortNames: map['useShortNames'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VolleyballScoreboardState &&
          teamA == other.teamA &&
          teamB == other.teamB &&
          scoreA == other.scoreA &&
          scoreB == other.scoreB &&
          currentSet == other.currentSet &&
          setsA == other.setsA &&
          setsB == other.setsB &&
          servingTeam == other.servingTeam &&
          eventTag == other.eventTag &&
          toastMessage == other.toastMessage &&
          anchorPosition == other.anchorPosition &&
          matchClock == other.matchClock &&
          colorA == other.colorA &&
          colorB == other.colorB &&
          teamAShort == other.teamAShort &&
          teamBShort == other.teamBShort &&
          useShortNames == other.useShortNames;

  @override
  int get hashCode => Object.hash(
    teamA,
    teamB,
    scoreA,
    scoreB,
    currentSet,
    setsA,
    setsB,
    servingTeam,
    eventTag,
    toastMessage,
    anchorPosition,
    matchClock,
    colorA,
    colorB,
    teamAShort,
    teamBShort,
    useShortNames,
  );
}

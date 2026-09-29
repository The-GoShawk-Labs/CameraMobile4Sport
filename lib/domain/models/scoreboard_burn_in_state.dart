import 'package:flutter/foundation.dart';
import 'package:volleylive/domain/models/match_recording_metadata.dart';
import 'package:volleylive/domain/models/match_session.dart';

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
  final String? eventTag;   // e.g. "ACE!", "BLOCK!", "TIMEOUT"
  final String? toastMessage;

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
  });

  /// Factory creating state directly from the app's [MatchSession]
  factory VolleyballScoreboardState.fromMatchSession(
    MatchSession session, {
    String? eventTag,
    String? toastMessage,
  }) {
    String serverStr = 'NONE';
    if (session.currentServer == ServingTeam.teamA) {
      serverStr = 'A';
    } else if (session.currentServer == ServingTeam.teamB) {
      serverStr = 'B';
    }

    final rawToast = toastMessage ?? eventTag;
    final effectiveToast = ScoreTimelineEntry.isDisplayableSpecialBanner(rawToast)
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
    );
  }

  Map<String, dynamic> toMap() => {
    'teamA': teamA,
    'teamB': teamB,
    'teamAName': teamA,
    'teamBName': teamB,
    'scoreA': scoreA,
    'scoreB': scoreB,
    'currentSet': currentSet,
    'setsA': setsA,
    'setsB': setsB,
    'servingTeam': servingTeam,
    'eventTag': eventTag ?? toastMessage ?? '',
    'toastMessage': toastMessage ?? eventTag ?? '',
  };

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
          toastMessage == other.toastMessage;

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
  );
}

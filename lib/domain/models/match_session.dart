import 'package:flutter/material.dart';

enum ServingTeam { teamA, teamB, none }

enum MatchSport {
  volleyball,
  beachVolleyball,
  basketball,
  football,
  generic,
}

extension MatchSportExtension on MatchSport {
  String get displayName {
    switch (this) {
      case MatchSport.volleyball:
        return 'Siatkówka Halowa';
      case MatchSport.beachVolleyball:
        return 'Siatkówka Plażowa';
      case MatchSport.basketball:
        return 'Koszykówka';
      case MatchSport.football:
        return 'Piłka Nożna / Futsal';
      case MatchSport.generic:
        return 'Sport Ogólny / Inny';
    }
  }

  String get shortName {
    switch (this) {
      case MatchSport.volleyball:
        return 'VOLLEY';
      case MatchSport.beachVolleyball:
        return 'BEACH';
      case MatchSport.basketball:
        return 'BASKET';
      case MatchSport.football:
        return 'SOCCER';
      case MatchSport.generic:
        return 'SPORT';
    }
  }

  String get periodLabel {
    switch (this) {
      case MatchSport.volleyball:
      case MatchSport.beachVolleyball:
        return 'SET';
      case MatchSport.basketball:
        return 'KWARTA';
      case MatchSport.football:
        return 'POŁOWA';
      case MatchSport.generic:
        return 'RUNDA';
    }
  }

  IconData get icon {
    switch (this) {
      case MatchSport.volleyball:
        return Icons.sports_volleyball;
      case MatchSport.beachVolleyball:
        return Icons.wb_sunny_rounded;
      case MatchSport.basketball:
        return Icons.sports_basketball;
      case MatchSport.football:
        return Icons.sports_soccer;
      case MatchSport.generic:
        return Icons.sports;
    }
  }

  List<int> get pointIncrements {
    switch (this) {
      case MatchSport.basketball:
        return [1, 2, 3];
      case MatchSport.volleyball:
      case MatchSport.beachVolleyball:
      case MatchSport.football:
      case MatchSport.generic:
        return [1];
    }
  }
}

class MatchSet {
  final int setNumber;
  final int scoreA;
  final int scoreB;
  final String? winner;

  const MatchSet({
    required this.setNumber,
    required this.scoreA,
    required this.scoreB,
    this.winner,
  });

  Map<String, dynamic> toJson() => {
    'setNumber': setNumber,
    'scoreA': scoreA,
    'scoreB': scoreB,
    'winner': winner,
  };

  factory MatchSet.fromJson(Map<String, dynamic> json) => MatchSet(
    setNumber: json['setNumber'] as int,
    scoreA: json['scoreA'] as int,
    scoreB: json['scoreB'] as int,
    winner: json['winner'] as String?,
  );
}

class MatchSession {
  final String id;
  final DateTime createdAt;
  final MatchSport sport;
  final String teamA;
  final String teamB;
  final Color teamAColor;
  final Color teamBColor;
  final int setsA;
  final int setsB;
  final int currentSetPointsA;
  final int currentSetPointsB;
  final int currentSetNumber;
  final List<MatchSet> setsHistory;
  final ServingTeam currentServer;
  final int timeoutsA;
  final int timeoutsB;
  final int substitutionsA;
  final int substitutionsB;
  final int foulsA;
  final int foulsB;
  final bool isMatchOver;
  final String? matchWinner;
  final String pairingCode;
  final String? tournamentName;

  const MatchSession({
    required this.id,
    required this.createdAt,
    this.sport = MatchSport.volleyball,
    required this.teamA,
    required this.teamB,
    this.teamAColor = const Color(0xFF00E5FF),
    this.teamBColor = const Color(0xFFFFAB00),
    this.setsA = 0,
    this.setsB = 0,
    this.currentSetPointsA = 0,
    this.currentSetPointsB = 0,
    this.currentSetNumber = 1,
    this.setsHistory = const [],
    this.currentServer = ServingTeam.teamA,
    this.timeoutsA = 0,
    this.timeoutsB = 0,
    this.substitutionsA = 0,
    this.substitutionsB = 0,
    this.foulsA = 0,
    this.foulsB = 0,
    this.isMatchOver = false,
    this.matchWinner,
    required this.pairingCode,
    this.tournamentName,
  });

  String get periodDisplay => '${sport.periodLabel} $currentSetNumber';

  MatchSession copyWith({
    String? id,
    DateTime? createdAt,
    MatchSport? sport,
    String? teamA,
    String? teamB,
    Color? teamAColor,
    Color? teamBColor,
    int? setsA,
    int? setsB,
    int? currentSetPointsA,
    int? currentSetPointsB,
    int? currentSetNumber,
    List<MatchSet>? setsHistory,
    ServingTeam? currentServer,
    int? timeoutsA,
    int? timeoutsB,
    int? substitutionsA,
    int? substitutionsB,
    int? foulsA,
    int? foulsB,
    bool? isMatchOver,
    String? matchWinner,
    String? pairingCode,
    String? tournamentName,
  }) {
    return MatchSession(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      sport: sport ?? this.sport,
      teamA: teamA ?? this.teamA,
      teamB: teamB ?? this.teamB,
      teamAColor: teamAColor ?? this.teamAColor,
      teamBColor: teamBColor ?? this.teamBColor,
      setsA: setsA ?? this.setsA,
      setsB: setsB ?? this.setsB,
      currentSetPointsA: currentSetPointsA ?? this.currentSetPointsA,
      currentSetPointsB: currentSetPointsB ?? this.currentSetPointsB,
      currentSetNumber: currentSetNumber ?? this.currentSetNumber,
      setsHistory: setsHistory ?? this.setsHistory,
      currentServer: currentServer ?? this.currentServer,
      timeoutsA: timeoutsA ?? this.timeoutsA,
      timeoutsB: timeoutsB ?? this.timeoutsB,
      substitutionsA: substitutionsA ?? this.substitutionsA,
      substitutionsB: substitutionsB ?? this.substitutionsB,
      foulsA: foulsA ?? this.foulsA,
      foulsB: foulsB ?? this.foulsB,
      isMatchOver: isMatchOver ?? this.isMatchOver,
      matchWinner: matchWinner ?? this.matchWinner,
      pairingCode: pairingCode ?? this.pairingCode,
      tournamentName: tournamentName ?? this.tournamentName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'sport': sport.name,
    'teamA': teamA,
    'teamB': teamB,
    'teamAColor': teamAColor.toARGB32(),
    'teamBColor': teamBColor.toARGB32(),
    'setsA': setsA,
    'setsB': setsB,
    'currentSetPointsA': currentSetPointsA,
    'currentSetPointsB': currentSetPointsB,
    'currentSetNumber': currentSetNumber,
    'setsHistory': setsHistory.map((s) => s.toJson()).toList(),
    'currentServer': currentServer.name,
    'timeoutsA': timeoutsA,
    'timeoutsB': timeoutsB,
    'substitutionsA': substitutionsA,
    'substitutionsB': substitutionsB,
    'foulsA': foulsA,
    'foulsB': foulsB,
    'isMatchOver': isMatchOver,
    'matchWinner': matchWinner,
    'pairingCode': pairingCode,
    'tournamentName': tournamentName,
  };

  factory MatchSession.fromJson(Map<String, dynamic> json) => MatchSession(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    sport: MatchSport.values.firstWhere((e) => e.name == json['sport'], orElse: () => MatchSport.volleyball),
    teamA: json['teamA'] as String,
    teamB: json['teamB'] as String,
    teamAColor: Color(json['teamAColor'] as int),
    teamBColor: Color(json['teamBColor'] as int),
    setsA: json['setsA'] as int,
    setsB: json['setsB'] as int,
    currentSetPointsA: json['currentSetPointsA'] as int,
    currentSetPointsB: json['currentSetPointsB'] as int,
    currentSetNumber: json['currentSetNumber'] as int,
    setsHistory: (json['setsHistory'] as List<dynamic>?)
        ?.map((s) => MatchSet.fromJson(s as Map<String, dynamic>))
        .toList() ?? [],
    currentServer: ServingTeam.values.firstWhere((e) => e.name == json['currentServer'], orElse: () => ServingTeam.teamA),
    timeoutsA: json['timeoutsA'] as int? ?? 0,
    timeoutsB: json['timeoutsB'] as int? ?? 0,
    substitutionsA: json['substitutionsA'] as int? ?? 0,
    substitutionsB: json['substitutionsB'] as int? ?? 0,
    foulsA: json['foulsA'] as int? ?? 0,
    foulsB: json['foulsB'] as int? ?? 0,
    isMatchOver: json['isMatchOver'] as bool? ?? false,
    matchWinner: json['matchWinner'] as String?,
    pairingCode: json['pairingCode'] as String? ?? 'VL-1000',
    tournamentName: json['tournamentName'] as String?,
  );
}

package com.goshawk.volleylive.stream

data class VolleyballScoreboardData(
    val teamA: String = "TEAM A",
    val teamB: String = "TEAM B",
    val scoreA: Int = 0,
    val scoreB: Int = 0,
    val currentSet: Int = 1,
    val setsA: Int = 0,
    val setsB: Int = 0,
    val servingTeam: String = "NONE",
    val eventTag: String = "",
    val toastMessage: String = "",
    val anchorPosition: String = "topLeft",
    val matchClock: String = "",
    val colorA: Int = 0xFF00B4D8.toInt(),
    val colorB: Int = 0xFFEF4444.toInt(),
    val teamAShort: String = "",
    val teamBShort: String = "",
    val useShortNames: Boolean = false
)

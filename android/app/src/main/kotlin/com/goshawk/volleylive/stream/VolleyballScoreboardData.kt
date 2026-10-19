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
    val useShortNames: Boolean = false,
    val style: String = "tvProBroadcast"
) {
    val teamAShortCode: String
        get() = if (teamAShort.isNotBlank()) teamAShort.uppercase() else deriveShortCode(teamA)

    val teamBShortCode: String
        get() = if (teamBShort.isNotBlank()) teamBShort.uppercase() else deriveShortCode(teamB)

    companion object {
        fun deriveShortCode(name: String): String {
            val clean = name.trim()
            if (clean.isEmpty()) return "TEA"
            val parts = clean.split("\\s+".toRegex()).filter { it.isNotEmpty() }
            return when {
                parts.size >= 3 -> ("" + parts[0][0] + parts[1][0] + parts[2][0]).uppercase()
                parts.size == 2 -> {
                    val p0 = parts[0]
                    val p1 = parts[1]
                    if (p0.length >= 2) {
                        ("${p0.substring(0, 2)}${p1[0]}").uppercase()
                    } else {
                        ("${p0[0]}${p1.take(2)}").uppercase()
                    }
                }
                clean.length >= 3 -> clean.substring(0, 3).uppercase()
                else -> clean.uppercase().padEnd(3, ' ')
            }
        }
    }
}

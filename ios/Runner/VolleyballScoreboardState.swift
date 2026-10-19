import Foundation

struct VolleyballScoreboardState: Equatable {
    let teamA: String
    let teamB: String
    let scoreA: Int
    let scoreB: Int
    let currentSet: Int
    let setsA: Int
    let setsB: Int
    let servingTeam: String
    let eventTag: String
    let toastMessage: String
    let style: String

    static let empty = VolleyballScoreboardState(
        teamA: "TEAM A",
        teamB: "TEAM B",
        scoreA: 0,
        scoreB: 0,
        currentSet: 1,
        setsA: 0,
        setsB: 0,
        servingTeam: "NONE",
        eventTag: "",
        toastMessage: "",
        style: "tvProBroadcast"
    )
}

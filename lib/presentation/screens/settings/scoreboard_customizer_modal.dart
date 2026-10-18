import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/widgets/scoreboard_overlay.dart';

class ScoreboardCustomizerModal extends StatefulWidget {
  const ScoreboardCustomizerModal({super.key});

  @override
  State<ScoreboardCustomizerModal> createState() => _ScoreboardCustomizerModalState();
}

class _ScoreboardCustomizerModalState extends State<ScoreboardCustomizerModal> {
  late TextEditingController _teamAController;
  late TextEditingController _teamAShortController;
  late TextEditingController _teamBController;
  late TextEditingController _teamBShortController;

  @override
  void initState() {
    super.initState();
    final session = context.read<MatchProvider>().session;
    _teamAController = TextEditingController(text: session.teamA);
    _teamAShortController = TextEditingController(text: session.teamAShortCode);
    _teamBController = TextEditingController(text: session.teamB);
    _teamBShortController = TextEditingController(text: session.teamBShortCode);
  }

  @override
  void dispose() {
    _teamAController.dispose();
    _teamAShortController.dispose();
    _teamBController.dispose();
    _teamBShortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streamer = context.watch<StreamerProvider>();
    final match = context.watch<MatchProvider>();
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: mediaQuery.size.height * (isLandscape ? 0.95 : 0.90),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // UCHWYT ARKUSZA + NAGŁÓWEK
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune, color: AppTheme.cyanAccent, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Scoreboard Studio (WYSIWYG)',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Zamknij Studio',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // PRZEWIJANA ZAWARTOŚĆ (PODGLĄD 16:9 + KONTROLKI ZGODNE Z PRAWEM FITTSA)
              Flexible(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. PODGLĄD NA ŻYWO (STAŁY 16:9 LIVE PREVIEW OGRANICZONY W PIONIE)
                        Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: isLandscape ? 120 : 190,
                            ),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF090D14),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white12),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [Color(0xFF101929), Color(0xFF090D14)],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.remove_red_eye_outlined, size: 10, color: AppTheme.cyanAccent),
                                            SizedBox(width: 4),
                                            Text(
                                              'PODGLĄD 16:9 WYSIWYG',
                                              style: TextStyle(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.8,
                                                color: AppTheme.cyanAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    ScoreboardOverlay(
                                      session: match.session,
                                      style: streamer.scoreboardStyle,
                                      anchorPosition: streamer.scoreboardAnchorPosition,
                                      showServeIndicator: streamer.showServeIndicator,
                                      matchDuration: match.matchDuration,
                                      activeSpecialEvent: match.activeSpecialEvent,
                                      useThreeLetterAcronyms: streamer.useThreeLetterAcronyms,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),
                      // 2. WIZUALNY SELEKTOR 6 POZYCJI KOTWICZENIA (2 WIERSZE × 3 KOLUMNY, MIN 48 DP)
                      const Text(
                        'Pozycja Tablicy w Kadrze (6 Stref Kotwiczenia):',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildVisualAnchorSelector(
                        context,
                        streamer.scoreboardAnchorPosition,
                        streamer,
                      ),

                      const SizedBox(height: 16),

                      // 3. MOTYW SCOREBOARDU
                      const Text(
                        'Styl Motywu Telewizyjnego:',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ScoreboardThemeStyle.values.map((style) {
                          final isSelected = streamer.scoreboardStyle == style;
                          return SizedBox(
                            height: 44,
                            child: ChoiceChip(
                              label: Text(style.label),
                              selected: isSelected,
                              selectedColor: AppTheme.cyanAccent,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              onSelected: (val) {
                                if (val) streamer.setScoreboardStyle(style);
                              },
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 16),

                      // 4. NAZWY DRUŻYN, SKRÓTY TLA I KOLORYSTYKA (W STREFIE KCIUKA)
                      const Text(
                        'Drużyny, Skróty (TLA) i Kolorystyka:',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTeamEditorCard(
                        title: 'GOSPODARZE (TEAM A)',
                        nameController: _teamAController,
                        shortController: _teamAShortController,
                        currentColor: match.session.teamAColor,
                        onNameChanged: (val) => match.updateTeamsInfo(teamA: val),
                        onShortChanged: (val) => match.updateTeamsInfo(teamAShort: val),
                        onColorChanged: (c) => match.updateTeamColors(
                          colorA: c,
                          colorB: match.session.teamBColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildTeamEditorCard(
                        title: 'GOŚCIE (TEAM B)',
                        nameController: _teamBController,
                        shortController: _teamBShortController,
                        currentColor: match.session.teamBColor,
                        onNameChanged: (val) => match.updateTeamsInfo(teamB: val),
                        onShortChanged: (val) => match.updateTeamsInfo(teamBShort: val),
                        onColorChanged: (c) => match.updateTeamColors(
                          colorA: match.session.teamAColor,
                          colorB: c,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // 5. ELEMENTY WIDOCZNE
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Skróty 3-literowe (TLA, np. AZS vs LEG)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'Kompaktowy, wysoce czytelny format transmisyjny TV',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        ),
                        value: streamer.useThreeLetterAcronyms,
                        activeThumbColor: AppTheme.cyanAccent,
                        onChanged: streamer.toggleThreeLetterAcronyms,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Wskaźnik zagrywki (Piłka / Neon)',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        value: streamer.showServeIndicator,
                        activeThumbColor: AppTheme.cyanAccent,
                        onChanged: streamer.toggleServeIndicator,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Odliczanie czasu przerw (30s Overlay)',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        value: streamer.showTimeoutCountdown,
                        activeThumbColor: AppTheme.cyanAccent,
                        onChanged: streamer.toggleTimeoutCountdown,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  /// Wizualny selektor pozycji w kadrze meczowym 16:9 (min. 48x48 dp dla każdego kafelka)
  Widget _buildVisualAnchorSelector(
    BuildContext context,
    ScoreboardAnchorPosition current,
    StreamerProvider streamer,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C101A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildAnchorZoneTile(
                label: 'Góra Lewa',
                icon: Icons.north_west,
                pos: ScoreboardAnchorPosition.topLeft,
                selected: current == ScoreboardAnchorPosition.topLeft,
                onTap: () => streamer.setScoreboardAnchorPosition(ScoreboardAnchorPosition.topLeft),
              ),
              const SizedBox(width: 6),
              _buildAnchorZoneTile(
                label: 'Góra Środek',
                icon: Icons.north,
                pos: ScoreboardAnchorPosition.topCenter,
                selected: current == ScoreboardAnchorPosition.topCenter,
                onTap: () => streamer.setScoreboardAnchorPosition(ScoreboardAnchorPosition.topCenter),
              ),
              const SizedBox(width: 6),
              _buildAnchorZoneTile(
                label: 'Góra Prawa',
                icon: Icons.north_east,
                pos: ScoreboardAnchorPosition.topRight,
                selected: current == ScoreboardAnchorPosition.topRight,
                onTap: () => streamer.setScoreboardAnchorPosition(ScoreboardAnchorPosition.topRight),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildAnchorZoneTile(
                label: 'Dół Lewa',
                icon: Icons.south_west,
                pos: ScoreboardAnchorPosition.bottomLeft,
                selected: current == ScoreboardAnchorPosition.bottomLeft,
                onTap: () => streamer.setScoreboardAnchorPosition(ScoreboardAnchorPosition.bottomLeft),
              ),
              const SizedBox(width: 6),
              _buildAnchorZoneTile(
                label: 'Dół Środek',
                icon: Icons.south,
                pos: ScoreboardAnchorPosition.bottomCenter,
                selected: current == ScoreboardAnchorPosition.bottomCenter,
                onTap: () => streamer.setScoreboardAnchorPosition(ScoreboardAnchorPosition.bottomCenter),
              ),
              const SizedBox(width: 6),
              _buildAnchorZoneTile(
                label: 'Dół Prawa',
                icon: Icons.south_east,
                pos: ScoreboardAnchorPosition.bottomRight,
                selected: current == ScoreboardAnchorPosition.bottomRight,
                onTap: () => streamer.setScoreboardAnchorPosition(ScoreboardAnchorPosition.bottomRight),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnchorZoneTile({
    required String label,
    required IconData icon,
    required ScoreboardAnchorPosition pos,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.cyanAccent.withValues(alpha: 0.18)
                  : const Color(0xFF141A26),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppTheme.cyanAccent : Colors.white12,
                width: selected ? 1.8 : 1.0,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppTheme.cyanAccent : Colors.white70,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? AppTheme.cyanAccent : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamEditorCard({
    required String title,
    required TextEditingController nameController,
    required TextEditingController shortController,
    required Color currentColor,
    required ValueChanged<String> onNameChanged,
    required ValueChanged<String> onShortChanged,
    required ValueChanged<Color> onColorChanged,
  }) {
    final colors = [
      const Color(0xFF00E5FF),
      const Color(0xFFFFAB00),
      const Color(0xFF00E676),
      const Color(0xFFFF1744),
      const Color(0xFF7C4DFF),
      const Color(0xFFFFFFFF),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: currentColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: currentColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: nameController,
                  onChanged: onNameChanged,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Pełna nazwa',
                    labelStyle: const TextStyle(fontSize: 10, color: Colors.white54),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF0B101B),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: shortController,
                  onChanged: onShortChanged,
                  maxLength: 3,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    labelText: 'TLA',
                    labelStyle: const TextStyle(fontSize: 10, color: Colors.white54),
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF0B101B),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Selektor kolorów zgodny z Prawem Fittsa (strefy dotyku 44x44 dp)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: colors.map((c) {
              final isSel = c.toARGB32() == currentColor.toARGB32();
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onColorChanged(c),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: isSel
                            ? Border.all(color: Colors.white, width: 2.5)
                            : Border.all(color: Colors.white24, width: 1),
                        boxShadow: isSel
                            ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)]
                            : null,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

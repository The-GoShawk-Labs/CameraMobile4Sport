import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/widgets/scoreboard_overlay.dart';

class ScoreboardCustomizerModal extends StatelessWidget {
  const ScoreboardCustomizerModal({super.key});

  @override
  Widget build(BuildContext context) {
    final streamer = context.watch<StreamerProvider>();
    final match = context.watch<MatchProvider>();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune, color: AppTheme.cyanAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Scoreboard Studio',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 1. PODGLĄD NA ŻYWO (16:9 LIVE PREVIEW Z NAKŁADKĄ I KOTWICĄ)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF090D14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Tło boiska
                    const Image(
                      image: AssetImage('assets/images/court_bg.png'),
                      fit: BoxFit.cover,
                      opacity: AlwaysStoppedAnimation(0.2),
                    ),

                    // Etykieta podglądu
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

                    // Tablica wyników pozycjonowana w 16:9
                    ScoreboardOverlay(
                      session: match.session,
                      style: streamer.scoreboardStyle,
                      anchorPosition: streamer.scoreboardAnchorPosition,
                      showServeIndicator: streamer.showServeIndicator,
                      matchDuration: match.matchDuration,
                      activeSpecialEvent: match.activeSpecialEvent,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 2. WIZUALNY SELEKTOR 6 POZYCJI KOTWICZENIA (2 WIERSZE × 3 KOLUMNY)
            const Text(
              'Pozycja Tablicy w Kadrze (6 Stref Kotwiczenia):',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildVisualAnchorSelector(context, streamer.scoreboardAnchorPosition, streamer),

            const SizedBox(height: 20),

            // 3. MOTYW SCOREBOARDU
            const Text(
              'Styl Motywu Telewizyjnego:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ScoreboardThemeStyle.values.map((style) {
                final isSelected = streamer.scoreboardStyle == style;
                return ChoiceChip(
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
                );
              }).toList(),
            ),

            const SizedBox(height: 18),

            // 4. KOLORYSTYKA DRUŻYN
            const Text(
              'Kolorystyka Drużyn:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildColorPickerItem(
                    label: match.session.teamA,
                    currentColor: match.session.teamAColor,
                    onColorChanged: (c) => match.updateTeamColors(
                      colorA: c,
                      colorB: match.session.teamBColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildColorPickerItem(
                    label: match.session.teamB,
                    currentColor: match.session.teamBColor,
                    onColorChanged: (c) => match.updateTeamColors(
                      colorA: match.session.teamAColor,
                      colorB: c,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // 5. ELEMENTY WIDOCZNE
            SwitchListTile(
              title: const Text('Wskaźnik zagrywki (Piłka / Neon)', style: TextStyle(color: Colors.white, fontSize: 13)),
              value: streamer.showServeIndicator,
              activeThumbColor: AppTheme.cyanAccent,
              onChanged: streamer.toggleServeIndicator,
            ),
            SwitchListTile(
              title: const Text('Odliczanie czasu przerw (30s Overlay)', style: TextStyle(color: Colors.white, fontSize: 13)),
              value: streamer.showTimeoutCountdown,
              activeThumbColor: AppTheme.cyanAccent,
              onChanged: streamer.toggleTimeoutCountdown,
            ),
          ],
        ),
      ),
    );
  }

  /// Wizualny selektor pozycji w kadrze meczowym 16:9
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
          // Linia górna (Góra Lewa, Góra Środek, Góra Prawa)
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
          // Linia dolna (Dół Lewa, Dół Środek, Dół Prawa)
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.cyanAccent.withValues(alpha: 0.18) : const Color(0xFF141A26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.cyanAccent : Colors.white12,
              width: selected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
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
    );
  }

  Widget _buildColorPickerItem({
    required String label,
    required Color currentColor,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: colors.map((c) {
              final isSel = c.toARGB32() == currentColor.toARGB32();
              return GestureDetector(
                onTap: () => onColorChanged(c),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: isSel ? Border.all(color: Colors.white, width: 2) : null,
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

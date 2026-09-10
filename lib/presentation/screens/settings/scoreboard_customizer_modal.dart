import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/theme/app_theme.dart';
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
                const Text(
                  'Scoreboard Studio',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // PODGLĄD NA ŻYWO (LIVE PREVIEW)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF090D14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
                image: const DecorationImage(
                  image: AssetImage('assets/images/court_bg.png'),
                  fit: BoxFit.cover,
                  opacity: 0.15,
                ),
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.remove_red_eye_outlined, size: 12, color: AppTheme.cyanAccent),
                      SizedBox(width: 4),
                      Text(
                        'PODGLĄD NAKŁADKI NA ŻYWO',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: AppTheme.cyanAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ScoreboardOverlay(
                    session: match.session,
                    style: streamer.scoreboardStyle,
                    showServeIndicator: streamer.showServeIndicator,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // MOTYW SCOREBOARDU
            const Text('Styl Motywu Telewizyjnego:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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

            // KOLORY DRUŻYN
            const Text('Kolorystyka Drużyn:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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

            // ELEMENTY WIDOCZNE
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

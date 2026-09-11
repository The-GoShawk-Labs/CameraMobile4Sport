import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:volleylive/core/router/app_router.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/widgets/sports_ui_components.dart';

class PhoneBMatchSetupScreen extends StatefulWidget {
  const PhoneBMatchSetupScreen({super.key});

  @override
  State<PhoneBMatchSetupScreen> createState() => _PhoneBMatchSetupScreenState();
}

class _PhoneBMatchSetupScreenState extends State<PhoneBMatchSetupScreen> {
  final _tournamentController = TextEditingController(text: 'LIGA MISTRZÓW MVP');
  final _teamAController = TextEditingController(text: 'AZS KRAKÓW');
  final _teamBController = TextEditingController(text: 'LEGIA WARSZAWA');
  Color _colorA = const Color(0xFF00E5FF);
  Color _colorB = const Color(0xFFFFAB00);
  MatchSport _selectedSport = MatchSport.volleyball;
  ScoreboardThemeStyle _selectedStyle = ScoreboardThemeStyle.tvProBroadcast;
  bool _isMatchCreated = false;

  final List<Color> _palette = [
    const Color(0xFF00E5FF),
    const Color(0xFFFFAB00),
    const Color(0xFF00E676),
    const Color(0xFFFF1744),
    const Color(0xFF7C4DFF),
    const Color(0xFFFFFFFF),
    const Color(0xFFFF4081),
    const Color(0xFF2979FF),
  ];

  @override
  void dispose() {
    _tournamentController.dispose();
    _teamAController.dispose();
    _teamBController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchProvider = context.watch<MatchProvider>();
    final streamerProvider = context.watch<StreamerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('KONFIGURACJA PRZEDMECZOWA'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: 'Wróć do menu',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRouter.initialRoute);
            }
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_isMatchCreated) ...[
                  // 1. WYBÓR DYSCYPLINY SPORTOWEJ / TABLICY
                  _buildSportHeader(),
                  const SizedBox(height: 10),
                  _buildSportSelectorGrid(),

                  const SizedBox(height: 18),

                  // 2. KARTA KONFIGURACJI DRUŻYN
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // NAZWA TURNIEJU / ROZGRYWEK
                        const Row(
                          children: [
                            Icon(Icons.emoji_events_outlined, color: Colors.white70, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'TYTUŁ ROZGRYWEK / TURNIEJU (OPCJONALNIE)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _tournamentController,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'np. Finał Pucharu Polski, Turniej U-18',
                            hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFF0D131F),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 12),

                        // GOSPODARZE (TEAM A)
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined, color: AppTheme.cyanAccent, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'GOSPODARZE (DRUŻYNA A)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: AppTheme.cyanAccent,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(color: _colorA, shape: BoxShape.circle),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _teamAController,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Nazwa drużyny gospodarzy',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: const Color(0xFF0D131F),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _colorA.withValues(alpha: 0.6)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _colorA, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildColorPickerRow(_colorA, (c) => setState(() => _colorA = c)),

                        const SizedBox(height: 18),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 12),

                        // GOŚCIE (TEAM B)
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined, color: AppTheme.amberAccent, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'GOŚCIE (DRUŻYNA B)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: AppTheme.amberAccent,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(color: _colorB, shape: BoxShape.circle),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _teamBController,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Nazwa drużyny gości',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: const Color(0xFF0D131F),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _colorB.withValues(alpha: 0.6)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _colorB, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildColorPickerRow(_colorB, (c) => setState(() => _colorB = c)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. WYBÓR STYLU GRAFICZNEGO TABLICY WYNIKÓW
                  _buildThemeSelector(),

                  const SizedBox(height: 20),

                  // PRZYCISK: UTWÓRZ MECZ & GENERUJ KOD DLA KAMERY
                  ElevatedButton(
                    onPressed: () {
                      matchProvider.startNewMatch(
                        teamA: _teamAController.text,
                        teamB: _teamBController.text,
                        teamAColor: _colorA,
                        teamBColor: _colorB,
                        sport: _selectedSport,
                        tournamentName: _tournamentController.text,
                      );
                      streamerProvider.setScoreboardStyle(_selectedStyle);
                      streamerProvider.startHostPairing(matchProvider.session.pairingCode);
                      context.read<P2PConnectionProvider>().hostSession(
                        pairingCode: matchProvider.session.pairingCode,
                      );
                      setState(() {
                        _isMatchCreated = true;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyanAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'POŁĄCZ ZE SMARTFONEM KAMERĄ (PHONE A)',
                          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // KROK 2: WIDOK WYGENEROWANEGO KODU QR I PAROWANIA ZE SMARTFONEM KAMERĄ
                  GlassCard(
                    borderColor: AppTheme.cyanAccent.withValues(alpha: 0.5),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_selectedSport.icon, color: AppTheme.cyanAccent, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _selectedSport.displayName.toUpperCase(),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.cyanAccent, letterSpacing: 1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              matchProvider.session.teamA,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _colorA),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text('VS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
                            ),
                            Text(
                              matchProvider.session.teamB,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _colorB),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // KOD QR ZE SZKLANĄ RAMKĄ
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: AppTheme.cyanGlow(blur: 20, opacity: 0.35),
                          ),
                          child: QrImageView(
                            data: 'volleylive://${matchProvider.session.pairingCode}',
                            version: QrVersions.auto,
                            size: 190.0,
                          ),
                        ),

                        const SizedBox(height: 18),

                        // PIGUŁKA KODU PIN ZE SKRÓTEM DO KOPIOWANIA
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: matchProvider.session.pairingCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Skopiowano kod do schowka!')),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF090E17),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.7)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  matchProvider.session.pairingCode,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.cyanAccent,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.copy, size: 14, color: AppTheme.cyanAccent),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),
                        const Text(
                          'Zeskanuj kod w Phone A (Kamera) lub wpisz powyższy PIN ręcznie.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // WSKAŹNIK STATUSU POŁĄCZENIA P2P
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: streamerProvider.cameraLinkState == CameraConnectionState.connected
                          ? AppTheme.greenLive.withValues(alpha: 0.15)
                          : AppTheme.amberAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: streamerProvider.cameraLinkState == CameraConnectionState.connected
                            ? AppTheme.greenLive
                            : AppTheme.amberAccent,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        PulseDot(
                          color: streamerProvider.cameraLinkState == CameraConnectionState.connected
                              ? AppTheme.greenLive
                              : AppTheme.amberAccent,
                          size: 10,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            streamerProvider.cameraLinkState == CameraConnectionState.connected
                                ? 'KAMERA PHONE A POŁĄCZONA (1080p 60FPS)'
                                : 'Oczekiwanie na połączenie z Phone A...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: streamerProvider.cameraLinkState == CameraConnectionState.connected
                                  ? AppTheme.greenLive
                                  : AppTheme.amberAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // PRZYCISK WEJŚCIA DO KOKPITU MECZU
                  ElevatedButton.icon(
                    onPressed: () {
                      context.go(AppRouter.scorerRoute);
                    },
                    icon: Icon(_selectedSport.icon, size: 20),
                    label: const Text('ROZPOCZNIJ TRANSMISJĘ & PRZEJDŹ DO KOKPITU', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.greenLive,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),

                  const SizedBox(height: 10),

                  TextButton.icon(
                    onPressed: () => setState(() => _isMatchCreated = false),
                    icon: const Icon(Icons.edit, size: 14, color: Colors.white70),
                    label: const Text('Edytuj parametry meczu', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSportHeader() {
    return const Row(
      children: [
        Icon(Icons.dashboard_customize_outlined, color: AppTheme.cyanAccent, size: 18),
        SizedBox(width: 8),
        Text(
          'WYBÓR RODZAJU TABLICY I DYSCYPLINY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildSportSelectorGrid() {
    final sports = [
      {
        'sport': MatchSport.volleyball,
        'title': 'SIATKÓWKA HALOWA',
        'desc': 'Sety do 25 pkt • Rotacja • Timeouty 30s',
        'icon': Icons.sports_volleyball,
        'color': AppTheme.cyanAccent,
      },
      {
        'sport': MatchSport.beachVolleyball,
        'title': 'SIATKÓWKA PLAŻOWA',
        'desc': '2 sety do 21 pkt • 2v2 • Zmiana stron',
        'icon': Icons.wb_sunny_rounded,
        'color': const Color(0xFFFFD54F),
      },
      {
        'sport': MatchSport.basketball,
        'title': 'KOSZYKÓWKA',
        'desc': '4 kwarty • Punkty +1, +2, +3 • Faule',
        'icon': Icons.sports_basketball,
        'color': const Color(0xFFFF9100),
      },
      {
        'sport': MatchSport.football,
        'title': 'PIŁKA NOŻNA / FUTSAL',
        'desc': '2 połowy • Gole • Kartki i rożne',
        'icon': Icons.sports_soccer,
        'color': AppTheme.greenLive,
      },
      {
        'sport': MatchSport.generic,
        'title': 'SPORT UNIWERSALNY',
        'desc': 'Uniwersalne punkty +1 / -1 • Rundy',
        'icon': Icons.sports,
        'color': const Color(0xFFB388FF),
      },
    ];

    return Column(
      children: sports.map((item) {
        final sport = item['sport'] as MatchSport;
        final isSelected = _selectedSport == sport;
        final color = item['color'] as Color;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedSport = sport;
                if (sport == MatchSport.beachVolleyball) {
                  _selectedStyle = ScoreboardThemeStyle.beachVolley;
                }
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.15) : const Color(0xFF101726),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? color : Colors.white12,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 10)] : null,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item['icon'] as IconData, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: isSelected ? Colors.white : Colors.white70,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item['desc'] as String,
                          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: color, size: 20)
                  else
                    const Icon(Icons.radio_button_unchecked, color: Colors.white24, size: 18),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildThemeSelector() {
    final styles = [
      {'style': ScoreboardThemeStyle.tvProBroadcast, 'label': 'TV Pro Broadcast'},
      {'style': ScoreboardThemeStyle.cyberGlow, 'label': 'Cyber Glow'},
      {'style': ScoreboardThemeStyle.minimalist, 'label': 'Minimalist Clean'},
      {'style': ScoreboardThemeStyle.beachVolley, 'label': 'Beach / Stadium'},
    ];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.palette_outlined, color: AppTheme.purpleAccent, size: 16),
              SizedBox(width: 8),
              Text(
                'MOTYW GRAFICZNY TRANSMISJI (SCOREBOARD OVERLAY)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: styles.map((item) {
              final style = item['style'] as ScoreboardThemeStyle;
              final isSelected = _selectedStyle == style;
              return ChoiceChip(
                label: Text(item['label'] as String),
                selected: isSelected,
                selectedColor: AppTheme.purpleAccent.withValues(alpha: 0.3),
                backgroundColor: const Color(0xFF0D131F),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.white60,
                ),
                side: BorderSide(
                  color: isSelected ? AppTheme.purpleAccent : Colors.white12,
                ),
                onSelected: (_) => setState(() => _selectedStyle = style),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPickerRow(Color selectedColor, ValueChanged<Color> onSelect) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _palette.map((color) {
        final isSel = color.toARGB32() == selectedColor.toARGB32();
        return GestureDetector(
          onTap: () => onSelect(color),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSel ? Colors.white : Colors.transparent,
                width: isSel ? 2.5 : 1,
              ),
              boxShadow: isSel ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)] : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

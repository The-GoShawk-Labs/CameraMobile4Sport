import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/router/app_router.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/screens/settings/scoreboard_customizer_modal.dart';
import 'package:volleylive/presentation/screens/settings/stream_settings_modal.dart';
import 'package:volleylive/presentation/widgets/sports_ui_components.dart';

class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final match = context.watch<MatchProvider>();
    final p2p = context.read<P2PConnectionProvider>();
    final camera = context.watch<CameraProvider>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // GÓRNY PASEK BADGE: PWA & TRYB SYSTEMU
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SportBadge(
                      label: 'PWA OFFLINE READY',
                      color: AppTheme.greenLive,
                      icon: Icons.offline_bolt_outlined,
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.style_outlined, color: AppTheme.cyanAccent, size: 20),
                          tooltip: 'Scoreboard Studio',
                          onPressed: () => showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => const ScoreboardCustomizerModal(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.stream, color: AppTheme.amberAccent, size: 20),
                          tooltip: 'Ustawienia Transmisji RTMP',
                          onPressed: () => showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => const StreamSettingsModal(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // LOGO & TYTUŁ APLIKACJI (HERO SECTION)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.cyanAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.cyanAccent, width: 2),
                          boxShadow: AppTheme.cyanGlow(blur: 16, opacity: 0.3),
                        ),
                        child: const Icon(Icons.videocam, color: AppTheme.cyanAccent, size: 30),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VolleyLive Pro',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'DUAL-DEVICE BROADCAST & SCORING SUITE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: AppTheme.cyanAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // SZYBKIE WZNOWIENIE MECZU (QUICK RESUME / CRASH RECOVERY)
                if (match.session.currentSetPointsA > 0 || match.session.currentSetPointsB > 0 || match.session.setsA > 0 || match.session.setsB > 0) ...[
                  GlassCard(
                    borderColor: AppTheme.amberAccent.withValues(alpha: 0.6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                PulseDot(color: AppTheme.amberAccent, size: 8),
                                SizedBox(width: 8),
                                Text(
                                  'MECZ W TOKU (WZNOWIENIE)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    color: AppTheme.amberAccent,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'PIN: ${match.session.pairingCode}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white60),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${match.session.teamA} vs ${match.session.teamB}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Set ${match.session.currentSetNumber} • Wynik: ${match.session.currentSetPointsA}:${match.session.currentSetPointsB} (Sety: ${match.session.setsA}-${match.session.setsB})',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                            ElevatedButton(
                              onPressed: () {
                                p2p.selectRole(DeviceRole.scorerPhoneB);
                                context.push(AppRouter.scorerRoute);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.amberAccent,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                minimumSize: const Size(80, 36),
                              ),
                              child: const Text('WZNOWIJ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // AKTYWNE NAGRYWANIE KAMERY W TLE (BACKGROUND MASTER REC RUNNING)
                if (camera.isRecording) ...[
                  GlassCard(
                    borderColor: AppTheme.redLive,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                PulseDot(color: AppTheme.redLive, size: 8),
                                SizedBox(width: 8),
                                Text(
                                  'KAMERA NAGRYWA W TLE (MASTER REC)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    color: AppTheme.redLive,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _formatDuration(camera.masterRecDuration),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => context.push(AppRouter.cameraRoute),
                                icon: const Icon(Icons.videocam, size: 14),
                                label: const Text('PODGLĄD KAMERY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.cyanAccent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => context.push(AppRouter.scorerRoute),
                                icon: const Icon(Icons.sports_volleyball, size: 14),
                                label: const Text('KOKPIT SĘDZIEGO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.amberAccent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // DEDYKOWANA KARTA: TRYB JEDNEGO SMARTFONA (ALL-IN-ONE)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00E5FF).withValues(alpha: 0.18),
                        const Color(0xFFFFAB00).withValues(alpha: 0.12),
                        const Color(0xFF0F1726),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.cyanAccent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.cyanAccent.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.cyanAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.cyanAccent),
                            ),
                            child: const Icon(Icons.phone_android, color: AppTheme.cyanAccent, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.cyanAccent.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'TRYB POJEDYNCZEGO URZĄDZENIA',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.cyanAccent,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'TRYB JEDNEGO SMARTFONA (ALL-IN-ONE)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Uruchom kamerę na statywie, wyjdź z widoku bez przerywania nagrywania i sędziuj lub wprowadzaj statystyki na tym samym telefonie!',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                      ),
                      const SizedBox(height: 14),
                      // SZYBKA SEKWENCJA KROKÓW 1-2-3
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                p2p.selectRole(DeviceRole.singlePhoneAllInOne);
                                context.push(AppRouter.cameraRoute);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.cyanAccent,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.camera_alt, size: 16),
                                  SizedBox(height: 2),
                                  Text('1. KAMERA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                p2p.selectRole(DeviceRole.singlePhoneAllInOne);
                                context.push(AppRouter.scorerRoute);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.amberAccent,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.sports_volleyball, size: 16),
                                  SizedBox(height: 2),
                                  Text('2. SĘDZIA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                p2p.selectRole(DeviceRole.singlePhoneAllInOne);
                                context.push(AppRouter.statisticianRoute);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.analytics_outlined, size: 16),
                                  SizedBox(height: 2),
                                  Text('3. STATYSTYKI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // SEPARATOR: TRYB DWÓCH SMARTFONÓW
                const Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white24)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'LUB TRYB DWÓCH SMARTFONÓW (P2P WEBRTC)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.white24)),
                  ],
                ),
                const SizedBox(height: 14),

                // KARTA: PHONE B (SCORER & REŻYSERKA)
                _buildRoleCard(
                  context: context,
                  title: 'PHONE B: PILOT / SĘDZIA + REŻYSERKA',
                  subtitle: 'Punktowanie dotykowe, obsługa grafiki TV, transmisja na YouTube/Meta, kontrola meczu.',
                  icon: Icons.sports_volleyball,
                  accentColor: AppTheme.amberAccent,
                  badgeText: 'KOKPIT SĘDZIEGO',
                  features: const ['Dotykowe +1 / Swipe -1', 'Transmisja RTMPS', 'Zarządzanie Tablicą TV'],
                  onTap: () {
                    p2p.selectRole(DeviceRole.scorerPhoneB);
                    context.push(AppRouter.scorerSetupRoute);
                  },
                ),

                const SizedBox(height: 14),

                // KARTA: PHONE A (KAMERA TRANSMISYJNA)
                _buildRoleCard(
                  context: context,
                  title: 'PHONE A: KAMERA (STATYW)',
                  subtitle: 'Bezprzewodowy obiektyw 1080p60, ciągły Master REC (Offline-Safe), WebRTC P2P.',
                  icon: Icons.camera_alt,
                  accentColor: AppTheme.cyanAccent,
                  badgeText: 'ŹRÓDŁO WIDEO',
                  features: const ['1080p 60FPS Video', 'Blokada AE/AF & Statyw', 'Ciągły Master REC'],
                  onTap: () {
                    p2p.selectRole(DeviceRole.cameraPhoneA);
                    context.push(AppRouter.cameraPairRoute);
                  },
                ),

                const SizedBox(height: 14),

                // KARTA: PANEL STATYSTYKA (STREFY BOISKA & HOMOGRAFIA)
                _buildRoleCard(
                  context: context,
                  title: 'TRYB STATYSTYKA (STREFY BOISKA)',
                  subtitle: 'Widok statycznej kamery z homografią stref (6, 9, 36 podstref), kalibracja ręczna i auto-algorytmy live.',
                  icon: Icons.analytics,
                  accentColor: const Color(0xFF00E676),
                  badgeText: 'ANALITYKA & HOMOGRAFIA',
                  features: const ['6 / 9 / 36 Stref (9x4)', 'Kalibracja Ręczna (P1-P4)', 'Algorytm Live Tracking', 'Heatmapa Zagrań'],
                  onTap: () {
                    p2p.selectRole(DeviceRole.statistician);
                    context.push(AppRouter.statisticianRoute);
                  },
                ),

                const SizedBox(height: 20),

                // DIAGNOSTYKA SYSTEMU
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDiagnosticItem(Icons.wifi_tethering, 'P2P WebRTC', 'Local Wi-Fi', AppTheme.greenLive),
                      _buildDiagnosticItem(Icons.videocam_outlined, 'Format', '1080p 60fps', AppTheme.cyanAccent),
                      _buildDiagnosticItem(Icons.save_outlined, 'Master REC', 'Offline Safe', AppTheme.amberAccent),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    required List<String> features,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppTheme.glassCardGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.15),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(icon, color: accentColor, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: accentColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 16),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: features.map((feat) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: accentColor, size: 10),
                      const SizedBox(width: 4),
                      Text(
                        feat,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticItem(IconData icon, String title, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '${d.inHours > 0 ? '${twoDigits(d.inHours)}:' : ''}$minutes:$seconds';
  }
}

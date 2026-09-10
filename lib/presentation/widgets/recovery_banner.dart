import 'package:flutter/material.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/presentation/widgets/sports_ui_components.dart';

class RecoveryBanner extends StatelessWidget {
  final CameraConnectionState connectionState;
  final bool isMasterRecordingActive;
  final VoidCallback? onManualReconnect;

  const RecoveryBanner({
    super.key,
    required this.connectionState,
    this.isMasterRecordingActive = false,
    this.onManualReconnect,
  });

  @override
  Widget build(BuildContext context) {
    if (connectionState == CameraConnectionState.connected) {
      return const SizedBox.shrink();
    }

    Color accentColor = AppTheme.amberAccent;
    IconData icon = Icons.sync_problem;
    String message = 'ŁĄCZENIE Z KAMERĄ...';

    if (connectionState == CameraConnectionState.reconnecting) {
      accentColor = AppTheme.redLive;
      icon = Icons.wifi_off;
      message = isMasterRecordingActive
          ? 'UTRACONO SYGNAŁ Z PHONE B — LOKALNE NAGRYWANIE KONTYNUOWANE'
          : 'UTRACONO OBRAZ Z KAMERY — WZNAWIANIE POŁĄCZENIA...';
    } else if (connectionState == CameraConnectionState.disconnected) {
      accentColor = const Color(0xFF90A4AE);
      icon = Icons.videocam_off;
      message = 'KAMERA ROZŁĄCZONA';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFA140A0D),
        border: Border(
          bottom: BorderSide(color: accentColor.withValues(alpha: 0.8), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          PulseDot(color: accentColor, size: 9),
          const SizedBox(width: 8),
          Icon(icon, color: accentColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (onManualReconnect != null && connectionState != CameraConnectionState.connecting) ...[
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onManualReconnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(64, 26),
              ),
              child: const Text('POŁĄCZ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/widgets/sports_ui_components.dart';

class CameraConnectionModal extends StatefulWidget {
  const CameraConnectionModal({super.key});

  @override
  State<CameraConnectionModal> createState() => _CameraConnectionModalState();
}

class _CameraConnectionModalState extends State<CameraConnectionModal> {
  final _ipController = TextEditingController(text: '192.168.68.51');
  bool _isConnecting = false;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect(P2PConnectionProvider p2p) async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    setState(() => _isConnecting = true);
    try {
      await p2p.joinSession(
        hostAddress: ip,
        pairingCode: 'VL-8492',
        role: DeviceRole.scorerPhoneB,
      );
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p2p = context.watch<P2PConnectionProvider>();
    final isConnected = p2p.connectionState == CameraConnectionState.connected;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
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
                      Icon(Icons.videocam, color: AppTheme.cyanAccent, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Połączenie z Kamerą Phone A',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // KARTA STATUSU POŁĄCZENIA
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isConnected
                      ? AppTheme.greenLive.withValues(alpha: 0.15)
                      : AppTheme.amberAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isConnected ? AppTheme.greenLive : AppTheme.amberAccent,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    PulseDot(
                      color: isConnected ? AppTheme.greenLive : AppTheme.amberAccent,
                      size: 10,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected
                                ? 'POŁĄCZONO Z KAMERĄ REALME'
                                : 'OCZEKIWANIE NA POŁĄCZENIE Z KAMERĄ',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: isConnected ? AppTheme.greenLive : AppTheme.amberAccent,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isConnected
                                ? 'Opóźnienie P2P: ${p2p.healthMetrics.latencyMs} ms • Klatki na żywo'
                                : 'Wpisz IP kamery Realme i naciśnij "POŁĄCZ"',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // POLE ADRESU IP
              TextField(
                controller: _ipController,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Adres IP Kamery (Phone A)',
                  labelStyle: const TextStyle(color: AppTheme.cyanAccent, fontSize: 12),
                  hintText: 'np. 192.168.68.51',
                  hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(Icons.wifi, color: AppTheme.cyanAccent, size: 20),
                  filled: true,
                  fillColor: AppTheme.surfaceCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cyanAccent, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // SZYBKIE PRESETY IP W LAN
              Row(
                children: [
                  const Text('Szybki wybór: ', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  InkWell(
                    onTap: () => _ipController.text = '192.168.68.51',
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        '192.168.68.51 (Realme)',
                        style: TextStyle(fontSize: 11, color: AppTheme.cyanAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // PRZYCISKI AKCJI
              if (isConnected)
                ElevatedButton.icon(
                  onPressed: () async {
                    await p2p.disconnect();
                  },
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('ROZŁĄCZ KAMERĘ', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _isConnecting ? null : () => _handleConnect(p2p),
                  icon: _isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.link, size: 18),
                  label: Text(
                    _isConnecting ? 'ŁĄCZENIE...' : 'POŁĄCZ Z TRANSMISJĄ KAMERY',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyanAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

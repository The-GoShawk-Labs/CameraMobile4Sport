import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';

class StreamSettingsModal extends StatefulWidget {
  const StreamSettingsModal({super.key});

  @override
  State<StreamSettingsModal> createState() => _StreamSettingsModalState();
}

class _StreamSettingsModalState extends State<StreamSettingsModal> {
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final streamer = context.read<StreamerProvider>();
    _urlController.text = streamer.destination.serverUrl;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streamer = context.watch<StreamerProvider>();

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
                  'Konfiguracja Transmisji RTMPS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // WYBÓR PLATFORMY
            const Text('Cel Transmisji:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            DropdownButtonFormField<StreamingPlatformType>(
              initialValue: streamer.destination.type,
              dropdownColor: AppTheme.surfaceCard,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: StreamingPlatformType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                );
              }).toList(),
              onChanged: (newType) {
                if (newType != null) {
                  _urlController.text = newType.defaultEndpoint;
                  streamer.updateDestination(
                    streamer.destination.copyWith(
                      type: newType,
                      serverUrl: newType.defaultEndpoint,
                    ),
                  );
                }
              },
            ),

            const SizedBox(height: 16),

            // SERVER URL
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'RTMPS Ingest Server URL',
                labelStyle: const TextStyle(color: AppTheme.cyanAccent),
                filled: true,
                fillColor: AppTheme.surfaceCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) {
                streamer.updateDestination(
                  streamer.destination.copyWith(serverUrl: val),
                );
              },
            ),

            const SizedBox(height: 16),

            // STREAM KEY
            TextField(
              controller: _keyController,
              obscureText: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Nowy Stream Key',
                labelStyle: const TextStyle(color: AppTheme.amberAccent),
                hintText: 'Wpisz klucz transmisji',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: AppTheme.surfaceCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save, color: AppTheme.greenLive),
                  onPressed: () async {
                    if (_keyController.text.isNotEmpty) {
                      await streamer.saveStreamKey(_keyController.text);
                      _keyController.clear();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Klucz zapisany w bezpiecznym magazynie!')),
                        );
                      }
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 8),

            // BADGE BEZPIECZEŃSTWA
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.greenLive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.greenLive.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield, color: AppTheme.greenLive, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zapisany klucz: ${streamer.maskedStreamKey}\n(Przechowywany w Secure Hardware Keystore)',
                      style: const TextStyle(fontSize: 10, color: AppTheme.greenLive),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // NAGRYWANIE PROGRAMOWE
            SwitchListTile(
              title: const Text('Lokalne Nagrywanie Programowe (MP4)', style: TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: const Text('Zapis wideo z nałożonym scoreboardem', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
              value: streamer.destination.isLocalProgramRecordingEnabled,
              activeThumbColor: AppTheme.cyanAccent,
              onChanged: (val) {
                streamer.updateDestination(
                  streamer.destination.copyWith(isLocalProgramRecordingEnabled: val),
                );
              },
            ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ZAPISZ I ZAMKNIJ', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

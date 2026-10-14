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
  Map<String, dynamic>? _hardwareValidationResult;
  bool _isValidatingHardware = false;

  @override
  void initState() {
    super.initState();
    final streamer = context.read<StreamerProvider>();
    _urlController.text = streamer.config.serverUrl;
    if (streamer.config.streamKey.isNotEmpty) {
      _keyController.text = streamer.config.streamKey;
    }
    _runHardwareValidation();
  }

  Future<void> _runHardwareValidation() async {
    setState(() => _isValidatingHardware = true);
    final streamer = context.read<StreamerProvider>();
    final result = await streamer.validateHardwareCapabilities();
    if (mounted) {
      setState(() {
        _hardwareValidationResult = result;
        _isValidatingHardware = false;
      });
    }
  }

  @override
  void dispose() {
    if (_keyController.text.trim().isNotEmpty) {
      final streamer = context.read<StreamerProvider>();
      streamer.saveStreamKey(_keyController.text.trim());
    }
    _keyController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streamer = context.watch<StreamerProvider>();
    final config = streamer.config;
    final complianceIssues = config.complianceIssues;

    final viewInsets = MediaQuery.of(context).viewInsets;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: 24 + viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.live_tv, color: AppTheme.redLive, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Konfiguracja RTMP / YouTube Live',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // PRESET SELECTOR (YouTube Live Presets & Custom)
            const Text(
              'Profil Transmisji (Preset Enkodera):',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<YouTubeLivePreset>(
              initialValue: config.preset,
              dropdownColor: AppTheme.surfaceCard,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: YouTubeLivePreset.values.map((preset) {
                return DropdownMenuItem(
                  value: preset,
                  child: Text(preset.label),
                );
              }).toList(),
              onChanged: (newPreset) {
                if (newPreset != null) {
                  streamer.selectPreset(newPreset);
                }
              },
            ),

            const SizedBox(height: 8),

            // TECHNICAL SPECIFICATIONS CARD
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (config.isCustomRtmp || config.isYouTubeCompliant)
                      ? AppTheme.greenLive.withValues(alpha: 0.4)
                      : AppTheme.amberAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        (config.isCustomRtmp || config.isYouTubeCompliant)
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        color: (config.isCustomRtmp || config.isYouTubeCompliant)
                            ? AppTheme.greenLive
                            : AppTheme.amberAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        config.isCustomRtmp
                            ? 'Własny RTMP (PC/Lokalna sieć) - gotowy do transmisji'
                            : (config.isYouTubeCompliant
                                ? 'Zgodność z YouTube Live Ingestion: 100%'
                                : 'Wymagana korekta parametrów dla YouTube'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: (config.isCustomRtmp || config.isYouTubeCompliant)
                              ? AppTheme.greenLive
                              : AppTheme.amberAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildSpecBadge('Rozdzielczość: ${config.resolution}'),
                      _buildSpecBadge('FPS: ${config.fps} fps'),
                      _buildSpecBadge('Wideo: ${config.videoBitrateKbps} kbps (CBR)'),
                      _buildSpecBadge('Profil: H.264 High 4.1'),
                      _buildSpecBadge('GOP: 2.0 s (Ścisłe)'),
                      _buildSpecBadge('Audio: AAC-LC 128 kbps (48kHz)'),
                    ],
                  ),
                  if (complianceIssues.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...complianceIssues.map((issue) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('• $issue', style: const TextStyle(color: AppTheme.amberAccent, fontSize: 11)),
                        )),
                  ],
                ],
              ),
            ),

            // CUSTOM CONFIGURATION CONTROLS (If preset == Custom)
            if (config.preset == YouTubeLivePreset.custom) ...[
              const SizedBox(height: 14),
              const Text('Własne parametry wideo:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: config.width == 1920 ? '1080p' : '720p',
                      dropdownColor: AppTheme.surfaceCard,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Rozdzielczość',
                        labelStyle: const TextStyle(color: AppTheme.cyanAccent, fontSize: 11),
                        filled: true,
                        fillColor: AppTheme.surfaceCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(value: '1080p', child: Text('1080p (1920x1080)')),
                        DropdownMenuItem(value: '720p', child: Text('720p (1280x720)')),
                      ],
                      onChanged: (val) {
                        final is1080 = val == '1080p';
                        streamer.updateStreamConfig(config.copyWith(
                          width: is1080 ? 1920 : 1280,
                          height: is1080 ? 1080 : 720,
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: config.fps,
                      dropdownColor: AppTheme.surfaceCard,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Klatki (FPS)',
                        labelStyle: const TextStyle(color: AppTheme.cyanAccent, fontSize: 11),
                        filled: true,
                        fillColor: AppTheme.surfaceCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 60, child: Text('60 FPS')),
                        DropdownMenuItem(value: 30, child: Text('30 FPS')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          streamer.updateStreamConfig(config.copyWith(fps: val));
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Bitrate wideo: ${config.videoBitrateKbps} kbps', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  const Spacer(),
                  const Text('CBR', style: TextStyle(color: AppTheme.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
              Slider(
                value: config.videoBitrateKbps.toDouble().clamp(1000, 12000),
                min: 1000,
                max: 12000,
                divisions: 22,
                activeColor: AppTheme.cyanAccent,
                onChanged: (val) {
                  streamer.updateStreamConfig(config.copyWith(videoBitrate: val.toInt() * 1000));
                },
              ),
            ],

            const SizedBox(height: 14),

            // INGEST SERVER URL
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Punkt końcowy (Ingest Server URL)',
                labelStyle: const TextStyle(color: AppTheme.cyanAccent),
                hintText: 'rtmps://a.rtmps.youtube.com/live2',
                filled: true,
                fillColor: AppTheme.surfaceCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: PopupMenuButton<String>(
                  icon: const Icon(Icons.arrow_drop_down, color: AppTheme.cyanAccent),
                  onSelected: (url) {
                    _urlController.text = url;
                    streamer.updateStreamConfig(config.copyWith(serverUrl: url));
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'rtmps://a.rtmps.youtube.com/live2',
                      child: Text('YouTube Live Główny (RTMPS)'),
                    ),
                    const PopupMenuItem(
                      value: 'rtmps://b.rtmps.youtube.com/live2?backup=1',
                      child: Text('YouTube Live Zapasowy (Backup)'),
                    ),
                    const PopupMenuItem(
                      value: 'rtmps://live-api-s.facebook.com:443/rtmp/',
                      child: Text('Facebook / Meta Live (RTMPS)'),
                    ),
                    const PopupMenuItem(
                      value: 'rtmp://127.0.0.1:1935/live/sport',
                      child: Text('Kabel USB / ADB Reverse (127.0.0.1:1935/live/sport)'),
                    ),
                    const PopupMenuItem(
                      value: 'rtmp://192.168.68.58:1935/live/sport',
                      child: Text('Wi-Fi komputer PC (192.168.68.58:1935/live/sport)'),
                    ),
                    const PopupMenuItem(
                      value: 'rtmp://192.168.1.100:1935/live/sport',
                      child: Text('Lokalny RTMP (Szablon: IP/live/sport)'),
                    ),
                    const PopupMenuItem(
                      value: 'rtmp://',
                      child: Text('Własny RTMP (Wpisz ręcznie)'),
                    ),
                  ],
                ),
              ),
              onChanged: (val) {
                streamer.updateStreamConfig(config.copyWith(serverUrl: val));
              },
            ),

            const SizedBox(height: 14),

            // STREAM KEY
            TextField(
              controller: _keyController,
              obscureText: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: config.isCustomRtmp
                    ? 'Klucz Transmisji (Opcjonalny dla własnego RTMP)'
                    : 'Klucz Transmisji (Stream Key)',
                labelStyle: const TextStyle(color: AppTheme.amberAccent),
                hintText: config.isCustomRtmp
                    ? 'Wpisz klucz lub zostaw puste jeśli jest w URL'
                    : 'Wklej klucz strumienia YouTube',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: AppTheme.surfaceCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save, color: AppTheme.greenLive),
                  tooltip: 'Zapisz bezpiecznie w Keystore',
                  onPressed: () async {
                    if (_keyController.text.trim().isNotEmpty) {
                      await streamer.saveStreamKey(_keyController.text.trim());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Klucz zapisany w sprzętowym magazynie Keystore!')),
                        );
                      }
                    }
                  },
                ),
              ),
              onChanged: (val) {
                streamer.updateStreamConfig(config.copyWith(streamKey: val.trim()));
              },
              onSubmitted: (val) async {
                if (val.trim().isNotEmpty) {
                  await streamer.saveStreamKey(val.trim());
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Klucz zapisany w sprzętowym magazynie Keystore!')),
                    );
                  }
                }
              },
            ),

            const SizedBox(height: 8),

            // SECURITY SHIELD
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.greenLive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.greenLive.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield, color: AppTheme.greenLive, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zapisany klucz: ${streamer.maskedStreamKey}\n(Szyfrowany w Android Keystore / iOS Keychain)',
                      style: const TextStyle(fontSize: 11, color: AppTheme.greenLive),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // HARDWARE ENCODER VALIDATION STATUS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF131E2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.memory, color: AppTheme.cyanAccent, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        'Walidacja sprzętowa enkodera:',
                        style: TextStyle(color: AppTheme.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (_isValidatingHardware)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyanAccent),
                        )
                      else
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.refresh, color: AppTheme.cyanAccent, size: 16),
                          onPressed: _runHardwareValidation,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_hardwareValidationResult != null) ...[
                    Text(
                      '• H.264 / AVC: ${_hardwareValidationResult!['isH264Supported'] == true ? "Wspierany (Hardware)" : "Brak wsparcia"}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                    Text(
                      '• Profil High (AVCProfileHigh): ${_hardwareValidationResult!['isHighProfileSupported'] == true ? "Wspierany" : "Brak wsparcia"}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                    Text(
                      '• Tryb stałego bitrate (CBR): ${_hardwareValidationResult!['isCbrSupported'] == true ? "Wspierany" : "Wspierany programowo"}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ] else
                    const Text('Sprawdzanie kodeków urządzenia...', style: TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // PROGRAM RECORDING SWITCH
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lokalne Nagrywanie Programowe (MP4)', style: TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: const Text('Równoległy zapis meczu na dysk z wypalonym scoreboardem', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
              value: config.isLocalProgramRecordingEnabled,
              activeThumbColor: AppTheme.cyanAccent,
              onChanged: (val) {
                streamer.updateStreamConfig(config.copyWith(isLocalProgramRecordingEnabled: val));
              },
            ),

            const SizedBox(height: 14),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('ZAPISZ I ZAMKNIJ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildSpecBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 10)),
    );
  }
}

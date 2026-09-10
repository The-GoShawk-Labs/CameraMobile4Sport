import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/camera_config.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';

class VideoSettingsModal extends StatelessWidget {
  const VideoSettingsModal({super.key});

  @override
  Widget build(BuildContext context) {
    final camera = context.watch<CameraProvider>();
    final settings = camera.settings;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141923),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // UCHWYT DOLNEGO ARKUSZA
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // NAGŁÓWEK
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.video_settings, color: AppTheme.cyanAccent, size: 24),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Konfiguracja Wideo i Transmisji',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Dostosuj jakość kodowania, klatkaż oraz przepustowość transmisji na żywo.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),

              // SEKCJA 1: ROZDZIELCZOŚĆ WIDEO
              const Text(
                'ROZDZIELCZOŚĆ KADRU',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
              ),
              const SizedBox(height: 10),
              Row(
                children: VideoResolution.values.map((res) {
                  final isSelected = settings.resolution == res;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => camera.setResolution(res),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.cyanAccent.withValues(alpha: 0.2) : AppTheme.surfaceCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppTheme.cyanAccent : Colors.white12,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                res.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? AppTheme.cyanAccent : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${res.width}x${res.height}',
                                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // SEKCJA 2: KLATKAŻ (FPS)
              const Text(
                'PŁYNNOŚĆ OBRAZU (FPS)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
              ),
              const SizedBox(height: 10),
              Row(
                children: VideoFps.values.map((fps) {
                  final isSelected = settings.fps == fps;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => camera.setFps(fps),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.cyanAccent.withValues(alpha: 0.2) : AppTheme.surfaceCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppTheme.cyanAccent : Colors.white12,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.speed,
                                size: 16,
                                color: isSelected ? AppTheme.cyanAccent : Colors.white60,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                fps.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? AppTheme.cyanAccent : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // SEKCJA 3: BITRATE (PRZEPŁYWNOŚĆ)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'PRZEPUSTOWOŚĆ (BITRATE)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.cyanAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${settings.bitrateMbps.toStringAsFixed(1)} Mbps',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: AppTheme.cyanAccent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: AppTheme.cyanAccent.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: settings.bitrateMbps.clamp(2.0, 16.0),
                  min: 2.0,
                  max: 16.0,
                  divisions: 14,
                  label: '${settings.bitrateMbps.toStringAsFixed(1)} Mbps',
                  onChanged: (val) => camera.setBitrate(val),
                ),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('2 Mbps (Oszczędny)', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                  Text('16 Mbps (HQ)', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Szacowane zużycie danych: ~${(settings.bitrateMbps * 450 / 1024).toStringAsFixed(1)} GB/mecz (2h)',
                  style: const TextStyle(fontSize: 10, color: AppTheme.amberAccent),
                ),
              ),
              const SizedBox(height: 16),

              // SEKCJA 4: PRZEŁĄCZNIKI FUNKCJONALNE
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Stabilizacja optyczna/cyfrowa',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Redukuje drgania przy montażu na statywach teleskopowych',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      value: settings.isStabilizationEnabled,
                      activeThumbColor: AppTheme.cyanAccent,
                      activeTrackColor: AppTheme.cyanAccent.withValues(alpha: 0.4),
                      onChanged: (_) => camera.toggleStabilization(),
                    ),
                    const Divider(color: Colors.white10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Rejestracja dźwięku z hali',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Wbudowany mikrofon smartfona jako źródło dźwięku transmisji',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      value: settings.isMicrophoneEnabled,
                      activeThumbColor: AppTheme.cyanAccent,
                      activeTrackColor: AppTheme.cyanAccent.withValues(alpha: 0.4),
                      onChanged: (_) => camera.toggleMicrophone(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // PRZYCISK ZAMKNIĘCIA I ZATWIERDZENIA
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'ZASTOSUJ USTAWIENIA',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

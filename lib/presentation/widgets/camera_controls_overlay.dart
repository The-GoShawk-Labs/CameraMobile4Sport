import 'package:flutter/material.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';

class CameraControlsOverlay extends StatefulWidget {
  final CameraProvider camera;
  final bool isLandscape;

  const CameraControlsOverlay({
    super.key,
    required this.camera,
    this.isLandscape = false,
  });

  @override
  State<CameraControlsOverlay> createState() => _CameraControlsOverlayState();
}

class _CameraControlsOverlayState extends State<CameraControlsOverlay> {
  bool _showExposureSlider = false;
  bool _showZoomSlider = false;

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera;
    final settings = camera.settings;

    if (!settings.isHudVisible) {
      return Positioned(
        top: widget.isLandscape ? 16 : 80,
        right: 16,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => camera.toggleHudVisibility(),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.6)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility, color: AppTheme.cyanAccent, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'POKAŻ HUD',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [

        // BOCZNY PANEL STEROWANIA KAMERĄ (ZOOM & EXPOSURE & FOCUS)
        Positioned(
          right: 16,
          top: widget.isLandscape ? 12 : null,
          bottom: widget.isLandscape ? 12 : 120,
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // PRZYCISK ROZWIJANIA SUWAKA EKSPOZYCJI (EV)
                  _buildControlButton(
                    icon: Icons.wb_sunny_outlined,
                    isActive: _showExposureSlider || settings.exposureOffset != 0.0,
                    badge: settings.exposureOffset == 0.0
                        ? 'EV'
                        : '${settings.exposureOffset > 0 ? '+' : ''}${settings.exposureOffset.toStringAsFixed(1)}',
                    onTap: () {
                      setState(() {
                        _showExposureSlider = !_showExposureSlider;
                        if (_showExposureSlider) _showZoomSlider = false;
                      });
                    },
                    tooltip: 'Kompensacja ekspozycji (Jasność)',
                  ),
                  SizedBox(height: widget.isLandscape ? 6 : 12),

                  // PRZYCISK ROZWIJANIA SUWAKA ZOOMU
                  _buildControlButton(
                    icon: Icons.zoom_in,
                    isActive: _showZoomSlider || settings.zoom > 1.05,
                    badge: '${settings.zoom.toStringAsFixed(1)}x',
                    onTap: () {
                      setState(() {
                        _showZoomSlider = !_showZoomSlider;
                        if (_showZoomSlider) _showExposureSlider = false;
                      });
                    },
                    tooltip: 'Przybliżenie / Zoom',
                  ),
                  SizedBox(height: widget.isLandscape ? 6 : 12),

                  // PRZEŁĄCZNIK BLOKADY OSTROŚCI (AF / FOCUS LOCK)
                  _buildControlButton(
                    icon: settings.isFocusLocked ? Icons.filter_center_focus : Icons.center_focus_weak,
                    isActive: settings.isFocusLocked,
                    activeColor: AppTheme.amberAccent,
                    badge: settings.isFocusLocked ? 'AF LOCK' : 'AF AUTO',
                    onTap: () => camera.toggleFocusLock(),
                    tooltip: 'Blokada ostrości (AF)',
                  ),
                  SizedBox(height: widget.isLandscape ? 6 : 12),

                  // PRZEŁĄCZNIK BLOKADY EKSPOZYCJI (AE LOCK)
                  _buildControlButton(
                    icon: settings.isExposureLocked ? Icons.lock : Icons.lock_open,
                    isActive: settings.isExposureLocked,
                    activeColor: AppTheme.amberAccent,
                    badge: settings.isExposureLocked ? 'AE LOCK' : 'AE AUTO',
                    onTap: () => camera.toggleExposureLock(),
                    tooltip: 'Blokada ekspozycji (AE)',
                  ),

                  if (settings.isManualFocusMode || settings.exposureOffset != 0.0 || settings.isExposureLocked || settings.isFocusLocked) ...[
                    SizedBox(height: widget.isLandscape ? 6 : 12),
                    // PRZYCISK RESETU DO USTAWIEŃ AUTOMATYCZNYCH
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                      tooltip: 'Resetuj AE/AF do Auto',
                      onPressed: () => camera.resetFocusAndExposure(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // ROZWIJANY SUWAK EKSPOZYCJI (EV)
        if (_showExposureSlider)
          Positioned(
            right: 76,
            top: widget.isLandscape ? 60 : 120,
            bottom: widget.isLandscape ? 80 : 130,
            child: SafeArea(
              child: Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xDD141923),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppTheme.amberAccent.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.wb_sunny, color: AppTheme.amberAccent, size: 18),
                    const SizedBox(height: 4),
                    Text(
                      '${settings.exposureOffset > 0 ? "+" : ""}${settings.exposureOffset.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.amberAccent,
                      ),
                    ),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                            activeTrackColor: AppTheme.amberAccent,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            overlayColor: AppTheme.amberAccent.withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            value: settings.exposureOffset.clamp(
                              settings.minExposureOffset,
                              settings.maxExposureOffset,
                            ),
                            min: settings.minExposureOffset,
                            max: settings.maxExposureOffset,
                            divisions: 20,
                            onChanged: (val) => camera.setExposureOffset(val),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.restart_alt, color: Colors.white70, size: 16),
                      tooltip: 'Reset EV (0.0)',
                      onPressed: () => camera.setExposureOffset(0.0),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ROZWIJANY SUWAK ZOOMU
        if (_showZoomSlider)
          Positioned(
            right: 76,
            top: widget.isLandscape ? 60 : 120,
            bottom: widget.isLandscape ? 80 : 130,
            child: SafeArea(
              child: Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xDD141923),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.zoom_in, color: AppTheme.cyanAccent, size: 18),
                    const SizedBox(height: 4),
                    Text(
                      '${settings.zoom.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.cyanAccent,
                      ),
                    ),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                            activeTrackColor: AppTheme.cyanAccent,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            overlayColor: AppTheme.cyanAccent.withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            value: settings.zoom.clamp(
                              settings.minZoomLevel,
                              settings.maxZoomLevel,
                            ),
                            min: settings.minZoomLevel,
                            max: settings.maxZoomLevel,
                            divisions: 28,
                            onChanged: (val) => camera.setZoom(val),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.replay_10, color: Colors.white70, size: 16),
                      tooltip: 'Reset Zoom (1.0x)',
                      onPressed: () => camera.setZoom(1.0),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required bool isActive,
    required String badge,
    required VoidCallback onTap,
    required String tooltip,
    Color activeColor = AppTheme.cyanAccent,
  }) {
    final parts = badge.split(' ');
    final isTwoLines = parts.length > 1;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 56,
          height: 56,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            color: isActive ? activeColor.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? activeColor : Colors.white24,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? activeColor : Colors.white,
                size: 20,
              ),
              const SizedBox(height: 2),
              if (isTwoLines) ...[
                Text(
                  parts[0],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                    color: isActive ? activeColor : Colors.white,
                  ),
                ),
                Text(
                  parts[1],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: isActive ? activeColor : Colors.white70,
                  ),
                ),
              ] else ...[
                Text(
                  badge,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                    color: isActive ? activeColor : Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FocusTargetIndicator extends StatelessWidget {
  final Offset position;
  final bool isLocked;

  const FocusTargetIndicator({
    super.key,
    required this.position,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 32,
      top: position.dy - 32,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 300),
          tween: Tween(begin: 1.5, end: 1.0),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  border: Border.all(
                    color: isLocked ? AppTheme.amberAccent : AppTheme.cyanAccent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isLocked ? AppTheme.amberAccent : AppTheme.cyanAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Positioned(
                      bottom: 2,
                      child: Text(
                        isLocked ? 'AE/AF LOCK' : 'AF',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: isLocked ? AppTheme.amberAccent : AppTheme.cyanAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

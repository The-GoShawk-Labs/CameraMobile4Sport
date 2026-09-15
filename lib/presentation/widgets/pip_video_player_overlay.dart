import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/court_homography.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/court_statistician_provider.dart';

/// Pływający odtwarzacz wideo PiP (Picture-in-Picture) ze swobodnym przesuwaniem i szybkimi powtórkami (-5s, -10s)
class PipVideoPlayerOverlay extends StatefulWidget {
  final CourtStatisticianProvider provider;
  final Size viewportSize;
  final String? videoUrl;

  const PipVideoPlayerOverlay({
    super.key,
    required this.provider,
    required this.viewportSize,
    this.videoUrl,
  });

  @override
  State<PipVideoPlayerOverlay> createState() => _PipVideoPlayerOverlayState();
}

class _PipVideoPlayerOverlayState extends State<PipVideoPlayerOverlay> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _statusMessage = 'Łączenie z kamerą Phone A...';
  Duration _simulatedPosition = const Duration(seconds: 45);
  final Duration _simulatedDuration = const Duration(minutes: 15);
  bool _isSimulatedPlaying = true;
  Timer? _simulatedTimer;
  String? _lastActionBadge;
  Timer? _badgeTimer;

  // Domyślny strumień testowy HLS/MP4
  static const String defaultSampleVideoUrl =
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _startSimulatedLoop();
  }

  void _initializePlayer() {
    final url = widget.videoUrl ?? defaultSampleVideoUrl;
    try {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        _controller = VideoPlayerController.networkUrl(uri)
          ..initialize().then((_) {
            if (mounted) {
              setState(() {
                _isInitialized = true;
                _hasError = false;
                _statusMessage = 'LIVE';
              });
              _controller?.setLooping(true);
              _controller?.play();
            }
          }).catchError((error) {
            if (mounted) {
              setState(() {
                _hasError = true;
                _statusMessage = 'Symulacja Strumienia Phone A';
              });
            }
          });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _statusMessage = 'Symulacja Strumienia Phone A';
        });
      }
    }
  }

  void _startSimulatedLoop() {
    _simulatedTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isSimulatedPlaying && mounted) {
        setState(() {
          final nextSeconds = _simulatedPosition.inSeconds + 1;
          _simulatedPosition = Duration(seconds: nextSeconds % _simulatedDuration.inSeconds);
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant PipVideoPlayerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.provider.lastRewindTriggerTime != oldWidget.provider.lastRewindTriggerTime &&
        widget.provider.lastRewindOffsetSeconds != null) {
      _rewind(widget.provider.lastRewindOffsetSeconds!);
    }
  }

  @override
  void dispose() {
    _simulatedTimer?.cancel();
    _badgeTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _rewind(int seconds) {
    _showActionBadge('-$seconds s REPLAY');

    if (_isInitialized && _controller != null) {
      final currentPos = _controller!.value.position;
      final target = currentPos - Duration(seconds: seconds);
      final clampedTarget = target < Duration.zero ? Duration.zero : target;
      _controller!.seekTo(clampedTarget);
      if (!_controller!.value.isPlaying) {
        _controller!.play();
      }
    } else {
      // Symulowany odtwarzacz
      final target = _simulatedPosition - Duration(seconds: seconds);
      setState(() {
        _simulatedPosition = target < Duration.zero ? Duration.zero : target;
      });
    }
  }

  void _togglePlayPause() {
    if (_isInitialized && _controller != null) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _showActionBadge('PAUZA');
      } else {
        _controller!.play();
        _showActionBadge('PLAY');
      }
      setState(() {});
    } else {
      setState(() {
        _isSimulatedPlaying = !_isSimulatedPlaying;
      });
      _showActionBadge(_isSimulatedPlaying ? 'PLAY' : 'PAUZA');
    }
  }

  void _cyclePlaybackSpeed() {
    final currentSpeed = widget.provider.playbackSpeed;
    final double nextSpeed;
    if (currentSpeed == 1.0) {
      nextSpeed = 0.5;
    } else if (currentSpeed == 0.5) {
      nextSpeed = 1.5;
    } else if (currentSpeed == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }

    widget.provider.setPlaybackSpeed(nextSpeed);
    if (_isInitialized && _controller != null) {
      _controller!.setPlaybackSpeed(nextSpeed);
    }
    _showActionBadge('${nextSpeed}x SPEED');
  }

  void _showActionBadge(String text) {
    _badgeTimer?.cancel();
    setState(() {
      _lastActionBadge = text;
    });
    _badgeTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _lastActionBadge = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    if (!provider.isPipVisible) {
      return const SizedBox();
    }

    CameraProvider? camera;
    try {
      camera = Provider.of<CameraProvider>(context);
    } catch (_) {
      // Bezpieczny fallback gdy CameraProvider nie jest obecny w hierarchii testów
    }

    final sizeState = provider.pipSizeState;
    final pipPos = provider.pipPosition;

    // Bezpieczne ograniczenie pozycji w obrębie ekranu
    final maxX = (widget.viewportSize.width - sizeState.width).clamp(0.0, widget.viewportSize.width);
    final maxY = (widget.viewportSize.height - sizeState.height).clamp(0.0, widget.viewportSize.height);
    final clampedX = pipPos.dx.clamp(0.0, maxX);
    final clampedY = pipPos.dy.clamp(0.0, maxY);

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        onPanUpdate: (details) {
          provider.updatePipPosition(details.delta, clampBounds: widget.viewportSize);
        },
        child: Container(
          width: sizeState.width,
          height: sizeState.height,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.amberAccent.withValues(alpha: 0.8),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.75),
                blurRadius: 18,
                spreadRadius: 3,
                offset: const Offset(0, 6),
              ),
              ...AppTheme.cyanGlow(blur: 12, opacity: 0.25),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: sizeState == PipSizeState.miniPill
                ? _buildMiniPillContent(camera)
                : _buildFullPipContent(sizeState, camera),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPillContent(CameraProvider? camera) {
    final bool isRec = camera != null && camera.isRecording;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFF0F172A),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Colors.white38),
                const SizedBox(width: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRec ? Colors.redAccent : AppTheme.greenLive,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    isRec ? 'REC LIVE' : 'PiP CAM',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                visualDensity: VisualDensity.compact,
                splashRadius: 14,
                icon: const Icon(Icons.replay_5, size: 18, color: AppTheme.amberAccent),
                onPressed: () => _rewind(5),
              ),
              const SizedBox(width: 4),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                visualDensity: VisualDensity.compact,
                splashRadius: 14,
                icon: const Icon(Icons.fullscreen, size: 18, color: Colors.white70),
                onPressed: () => widget.provider.togglePipExpanded(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFullPipContent(PipSizeState sizeState, CameraProvider? camera) {
    final bool isPlaying = _isInitialized && _controller != null
        ? _controller!.value.isPlaying
        : _isSimulatedPlaying;

    final Duration currentPos = _isInitialized && _controller != null
        ? _controller!.value.position
        : _simulatedPosition;

    final Duration totalDur = _isInitialized && _controller != null
        ? (_controller!.value.duration == Duration.zero ? _simulatedDuration : _controller!.value.duration)
        : _simulatedDuration;

    final bool hasLocalCamera = camera != null &&
        camera.isCameraInitialized &&
        camera.cameraController != null &&
        camera.cameraController!.value.isInitialized;

    final String displayStatus = camera != null && camera.isRecording
        ? '🔴 MASTER REC (1-PHONE)'
        : _statusMessage;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Podgląd Wideo (Kamera lokalna w trybie 1 smartfona, VideoPlayer lub Symulowany Kadr Boiska)
        if (hasLocalCamera)
          Builder(
            builder: (context) {
              final controller = camera.cameraController!;
              final pWidth = controller.value.previewSize?.width ?? 1920.0;
              final pHeight = controller.value.previewSize?.height ?? 1080.0;
              final sensorLong = pWidth > pHeight ? pWidth : pHeight;
              final sensorShort = pWidth > pHeight ? pHeight : pWidth;
              return Center(
                child: AspectRatio(
                  aspectRatio: sensorLong / sensorShort,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: sensorLong,
                      height: sensorShort,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
              );
            },
          )
        else if (_isInitialized && _controller != null && !_hasError)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width > 0 ? _controller!.value.size.width : 1920,
              height: _controller!.value.size.height > 0 ? _controller!.value.size.height : 1080,
              child: VideoPlayer(_controller!),
            ),
          )
        else
          _buildSimulatedCameraFeed(),

        // 2. Cień/Gradient dla czytelności kontrolek
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC070A10),
                Colors.transparent,
                Colors.transparent,
                Color(0xEE070A10),
              ],
              stops: [0.0, 0.25, 0.65, 1.0],
            ),
          ),
        ),

        // 3. Górny pasek nagłówka PiP (Drag handle, status, przyciski rozmiaru)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (camera != null && camera.isRecording) ? Colors.redAccent : AppTheme.greenLive,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    displayStatus,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                // Przycisk zwijania do Mini-Pill
                InkWell(
                  onTap: () => widget.provider.togglePipExpanded(),
                  child: Icon(
                    sizeState == PipSizeState.expanded ? Icons.unfold_less : Icons.unfold_more,
                    size: 15,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 6),
                // Przycisk ukrycia PiP
                InkWell(
                  onTap: () => widget.provider.togglePipVisibility(),
                  child: const Icon(Icons.close, size: 15, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),

        // 4. Nakładka z etykietą akcji (np. "-5s REPLAY", "0.5x SPEED")
        if (_lastActionBadge != null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.amberAccent, width: 1.5),
              ),
              child: Text(
                _lastActionBadge!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.amberAccent,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),

        // 5. Dolny pasek sterowania wideo i przewijania
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pasek postępu bufora / wideo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(currentPos),
                        style: const TextStyle(fontSize: 7.5, color: Colors.white70, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: totalDur.inMilliseconds > 0
                                ? (currentPos.inMilliseconds / totalDur.inMilliseconds).clamp(0.0, 1.0)
                                : 0.0,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.cyanAccent),
                            minHeight: 2.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(totalDur),
                        style: const TextStyle(fontSize: 7.5, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),

                // Przyciski sterujące: -10s, -5s, Play/Pause, Speed, Live
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Przycisk -10s
                      _buildControlButton(
                        label: '-10s',
                        icon: Icons.replay_10,
                        color: AppTheme.amberAccent,
                        onTap: () => _rewind(10),
                      ),
                      const SizedBox(width: 3),

                      // Przycisk -5s
                      _buildControlButton(
                        label: '-5s',
                        icon: Icons.replay_5,
                        color: AppTheme.amberAccent,
                        onTap: () => _rewind(5),
                      ),
                      const SizedBox(width: 3),

                      // Play / Pause
                      _buildControlButton(
                        label: isPlaying ? 'PAUZA' : 'PLAY',
                        icon: isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        onTap: _togglePlayPause,
                      ),
                      const SizedBox(width: 3),

                      // Speed (0.5x, 1.0x, 1.5x)
                      _buildControlButton(
                        label: '${widget.provider.playbackSpeed}x',
                        icon: Icons.speed,
                        color: AppTheme.cyanAccent,
                        onTap: _cyclePlaybackSpeed,
                      ),
                      const SizedBox(width: 3),

                      // Skok do LIVE
                      _buildControlButton(
                        label: 'LIVE',
                        icon: Icons.fiber_smart_record,
                        color: AppTheme.greenLive,
                        onTap: () {
                          if (_isInitialized && _controller != null) {
                            _controller!.seekTo(_controller!.value.duration);
                          } else {
                            setState(() {
                              _simulatedPosition = _simulatedDuration - const Duration(seconds: 2);
                            });
                          }
                          _showActionBadge('LIVE FEED');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulatedCameraFeed() {
    return Container(
      color: const Color(0xFF070F1E),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _SimulatedCourtPainter(),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_outlined, size: 24, color: AppTheme.cyanAccent),
                const SizedBox(height: 4),
                const Text(
                  'PODGLĄD LIVE Z PHONE A',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white70),
                ),
                Text(
                  '1080p @ 60 FPS • WebRTC Low Latency',
                  style: TextStyle(fontSize: 7.5, color: AppTheme.cyanAccent.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _SimulatedCourtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);

    // Krawędzie boiska
    final rect = Rect.fromCenter(center: center, width: size.width * 0.82, height: size.height * 0.65);
    canvas.drawRect(rect, paint);

    // Siatka
    canvas.drawLine(Offset(rect.left, center.dy), Offset(rect.right, center.dy), paint..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

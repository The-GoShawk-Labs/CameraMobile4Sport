import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/domain/services/native_stream_burner_bridge.dart';

/// Captures the authentic Flutter [ScoreboardOverlay] widget (with its active
/// broadcast theme, team colors, badges, and banners) and transmits its rasterized
/// RGBA PNG to the native streaming engine (StreamPack on Android / HaishinKit on iOS)
/// for zero-lag hardware video frame burn-in.
class ScoreboardWidgetBurner {
  final GlobalKey boundaryKey;
  final NativeStreamBurnerBridge bridge;

  bool _isCapturing = false;
  Uint8List? _lastBytes;
  int _lastCaptureTimeMs = 0;

  ScoreboardWidgetBurner({
    required this.boundaryKey,
    NativeStreamBurnerBridge? bridge,
  }) : bridge = bridge ?? NativeStreamBurnerBridge();

  static Uint8List? latestCapturedPngBytes;
  static String? latestOverlayImagePath;

  /// Rasterizes the exact ScoreboardOverlay widget into an RGBA PNG
  /// and updates the native video frame modifier texture and disk cache.
  Future<bool> captureAndPush({bool force = false}) async {
    if (_isCapturing) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _lastCaptureTimeMs > 0 && (now - _lastCaptureTimeMs) < 250) {
      return false;
    }
    final context = boundaryKey.currentContext;
    if (context == null) return false;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return false;
    }
    if (renderObject.debugNeedsPaint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        captureAndPush(force: force);
      });
      return false;
    }

    _isCapturing = true;
    ui.Image? image;
    try {
      // 2.0x pixel ratio yields a crisp, broadcast-quality HUD matching 1080p
      image = await renderObject.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return false;

      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      // Skip redundant transfers if pixels are identical, unless force is requested
      if (!force && _lastBytes != null && _areByteArraysEqual(_lastBytes!, bytes)) {
        return false;
      }
      _lastBytes = bytes;
      _lastCaptureTimeMs = now;
      latestCapturedPngBytes = bytes;
      _persistLatestImageToDiskAsync(bytes);

      await bridge.updateScoreboardOverlayBitmap(
        bytes: bytes,
        width: image.width,
        height: image.height,
      );
      return true;
    } catch (e) {
      debugPrint('[ScoreboardWidgetBurner] Capture failed: $e');
      return false;
    } finally {
      image?.dispose();
      _isCapturing = false;
    }
  }

  static void _persistLatestImageToDiskAsync(Uint8List bytes) {
    try {
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/scoreboard_overlay_latest.png');
      latestOverlayImagePath = file.path;
      file.writeAsBytes(bytes).catchError((_) => file);
    } catch (_) {}
  }

  /// Ensures a broadcast-quality PNG of the authentic scoreboard is available on disk
  /// for FFmpeg burning into recorded MP4 or live stream fallback.
  static Future<String?> ensureOverlayImageOnDisk({
    MatchSession? session,
    ScoreboardThemeStyle style = ScoreboardThemeStyle.tvProBroadcast,
    bool isPortrait = false,
  }) async {
    if (latestOverlayImagePath != null &&
        File(latestOverlayImagePath!).existsSync() &&
        File(latestOverlayImagePath!).lengthSync() > 0) {
      return latestOverlayImagePath;
    }

    final bytes = latestCapturedPngBytes ??
        (session != null
            ? await generateBroadcastOverlayPng(
                session: session,
                style: style,
                isPortrait: isPortrait,
              )
            : null);

    if (bytes != null && bytes.isNotEmpty) {
      try {
        final tempDir = Directory.systemTemp;
        final file = File(
          '${tempDir.path}/scoreboard_overlay_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(bytes, flush: true);
        latestOverlayImagePath = file.path;
        return file.path;
      } catch (e) {
        debugPrint('[ScoreboardWidgetBurner] Failed to write overlay image to disk: $e');
      }
    }
    return null;
  }

  /// Saves a high-resolution broadcast scoreboard PNG to disk for a specific session state.
  static Future<String?> saveOverlayPngToDisk({
    required MatchSession session,
    ScoreboardThemeStyle style = ScoreboardThemeStyle.tvProBroadcast,
    bool isPortrait = false,
    bool showServeIndicator = true,
    String? activeSpecialEvent,
    double pixelRatio = 2.0,
  }) async {
    final bytes = await generateBroadcastOverlayPng(
      session: session,
      style: style,
      isPortrait: isPortrait,
      showServeIndicator: showServeIndicator,
      activeSpecialEvent: activeSpecialEvent,
      pixelRatio: pixelRatio,
    );
    try {
      final tempDir = Directory.systemTemp;
      final file = File(
        '${tempDir.path}/scoreboard_overlay_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      latestOverlayImagePath = file.path;
      latestCapturedPngBytes = bytes;
      return file.path;
    } catch (e) {
      debugPrint('[ScoreboardWidgetBurner] Failed to write overlay PNG to disk: $e');
      return null;
    }
  }

  /// Programmatically generates a TV-broadcast-quality scoreboard PNG matching the
  /// exact layout and theme of the Flutter [ScoreboardOverlay] widget.
  static Future<Uint8List> generateBroadcastOverlayPng({
    required MatchSession session,
    ScoreboardThemeStyle style = ScoreboardThemeStyle.tvProBroadcast,
    bool isPortrait = false,
    bool showServeIndicator = true,
    String? activeSpecialEvent,
    double pixelRatio = 2.0,
  }) async {
    // Proportions matching ScoreboardOverlay:
    // Card height: 48 logical px (96 px @ 2.0x) + banner if event present (26 logical px)
    final bool hasBanner = (activeSpecialEvent != null && activeSpecialEvent.trim().isNotEmpty);
    final double cardHeight = 48.0 * pixelRatio;
    final double bannerHeight = hasBanner ? 26.0 * pixelRatio : 0.0;
    final double totalHeight = cardHeight + bannerHeight + 16.0 * pixelRatio;
    final double cardWidth = (isPortrait ? 580.0 : 700.0) * pixelRatio;
    final double totalWidth = cardWidth + 24.0 * pixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, totalWidth, totalHeight));

    final cardRect = Rect.fromLTWH(
      12.0 * pixelRatio,
      8.0 * pixelRatio,
      cardWidth,
      cardHeight,
    );
    final cardRRect = RRect.fromRectAndRadius(
      cardRect,
      Radius.circular(10.0 * pixelRatio),
    );

    // 1. Drop Shadow
    final shadowPaint = Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12.0 * pixelRatio);
    canvas.drawRRect(cardRRect.shift(Offset(0, 4.0 * pixelRatio)), shadowPaint);

    // 2. Card Background & Border according to active broadcast theme style
    final Color bgColor;
    final Color borderColor;
    switch (style) {
      case ScoreboardThemeStyle.cyberGlow:
        bgColor = const Color(0xEB0A0E17);
        borderColor = const Color(0xFF00E5FF);
        break;
      case ScoreboardThemeStyle.beachVolley:
        bgColor = const Color(0xF0E65100);
        borderColor = const Color(0xFFFFB300);
        break;
      case ScoreboardThemeStyle.minimalist:
        bgColor = const Color(0xF0141923);
        borderColor = const Color(0xFF333D52);
        break;
      case ScoreboardThemeStyle.tvProBroadcast:
        bgColor = const Color(0xF00D111A);
        borderColor = const Color(0xFF2E3A52);
        break;
      case ScoreboardThemeStyle.broadcastCompact3Letter:
        bgColor = const Color(0xF01A1E2E);
        borderColor = const Color(0xFFE6007E);
        break;
    }

    final bgPaint = Paint()..color = bgColor;
    canvas.drawRRect(cardRRect, bgPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * pixelRatio
      ..color = borderColor;
    canvas.drawRRect(cardRRect, borderPaint);

    // Clip inner content inside the rounded card
    canvas.save();
    canvas.clipRRect(cardRRect);

    // Geometry layout
    final double accentStripWidth = 6.0 * pixelRatio;
    final double pointsBoxWidth = 52.0 * pixelRatio;
    final double centerBoxWidth = 72.0 * pixelRatio;
    final Color teamACol = session.teamAColor;
    final Color teamBCol = session.teamBColor;

    // 3. Team A Left Accent Strip
    canvas.drawRect(
      Rect.fromLTWH(cardRect.left, cardRect.top, accentStripWidth, cardHeight),
      Paint()..color = teamACol,
    );

    // 4. Team B Right Accent Strip
    canvas.drawRect(
      Rect.fromLTWH(cardRect.right - accentStripWidth, cardRect.top, accentStripWidth, cardHeight),
      Paint()..color = teamBCol,
    );

    // 5. Center Period / Sets Section ("SET X" & "setsA-setsB")
    final double centerX = cardRect.center.dx;
    final centerBoxRect = Rect.fromCenter(
      center: Offset(centerX, cardRect.center.dy),
      width: centerBoxWidth,
      height: cardHeight,
    );
    canvas.drawRect(
      centerBoxRect,
      Paint()..color = const Color(0xFF090C12),
    );
    // Vertical separator borders
    final sepPaint = Paint()
      ..color = const Color(0xFF1F293D)
      ..strokeWidth = 1.0 * pixelRatio;
    canvas.drawLine(centerBoxRect.topLeft, centerBoxRect.bottomLeft, sepPaint);
    canvas.drawLine(centerBoxRect.topRight, centerBoxRect.bottomRight, sepPaint);

    final periodPainter = TextPainter(
      text: TextSpan(
        text: session.periodDisplay.toUpperCase(),
        style: TextStyle(
          color: Colors.white70,
          fontSize: 10.0 * pixelRatio,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    periodPainter.paint(
      canvas,
      Offset(centerX - periodPainter.width / 2, cardRect.top + 7.0 * pixelRatio),
    );

    final setsScorePainter = TextPainter(
      text: TextSpan(
        text: '${session.setsA}-${session.setsB}',
        style: TextStyle(
          color: const Color(0xFFFFB300),
          fontSize: 11.0 * pixelRatio,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    setsScorePainter.paint(
      canvas,
      Offset(centerX - setsScorePainter.width / 2, cardRect.top + 23.0 * pixelRatio),
    );

    // 6. Team A Points Box (Dark Navy #151C28)
    final teamAPointsRect = Rect.fromLTWH(
      centerBoxRect.left - pointsBoxWidth,
      cardRect.top,
      pointsBoxWidth,
      cardHeight,
    );
    canvas.drawRect(teamAPointsRect, Paint()..color = const Color(0xFF151C28));
    final scoreAPainter = TextPainter(
      text: TextSpan(
        text: '${session.currentSetPointsA}',
        style: TextStyle(
          color: teamACol,
          fontSize: 22.0 * pixelRatio,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    scoreAPainter.paint(
      canvas,
      Offset(
        teamAPointsRect.center.dx - scoreAPainter.width / 2,
        teamAPointsRect.center.dy - scoreAPainter.height / 2,
      ),
    );

    // 7. Team B Points Box (Dark Navy #151C28)
    final teamBPointsRect = Rect.fromLTWH(
      centerBoxRect.right,
      cardRect.top,
      pointsBoxWidth,
      cardHeight,
    );
    canvas.drawRect(teamBPointsRect, Paint()..color = const Color(0xFF151C28));
    final scoreBPainter = TextPainter(
      text: TextSpan(
        text: '${session.currentSetPointsB}',
        style: TextStyle(
          color: teamBCol,
          fontSize: 22.0 * pixelRatio,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    scoreBPainter.paint(
      canvas,
      Offset(
        teamBPointsRect.center.dx - scoreBPainter.width / 2,
        teamBPointsRect.center.dy - scoreBPainter.height / 2,
      ),
    );

    // 8. Team A Sets Badge (Pill with sets number)
    final double badgeWidth = 22.0 * pixelRatio;
    final double badgeHeight = 22.0 * pixelRatio;
    final double badgeAY = cardRect.center.dy - badgeHeight / 2;
    final double badgeAX = teamAPointsRect.left - badgeWidth - 8.0 * pixelRatio;
    final badgeARRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeAX, badgeAY, badgeWidth, badgeHeight),
      Radius.circular(6.0 * pixelRatio),
    );
    canvas.drawRRect(badgeARRect, Paint()..color = teamACol.withValues(alpha: 0.20));
    canvas.drawRRect(badgeARRect, Paint()..color = teamACol.withValues(alpha: 0.50)..style = PaintingStyle.stroke..strokeWidth = 1.0 * pixelRatio);
    final badgeAPainter = TextPainter(
      text: TextSpan(
        text: '${session.setsA}',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12.0 * pixelRatio,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badgeAPainter.paint(
      canvas,
      Offset(badgeAX + (badgeWidth - badgeAPainter.width) / 2, badgeAY + (badgeHeight - badgeAPainter.height) / 2),
    );

    // 9. Team B Sets Badge
    final double badgeBX = teamBPointsRect.right + 8.0 * pixelRatio;
    final badgeBRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeBX, badgeAY, badgeWidth, badgeHeight),
      Radius.circular(6.0 * pixelRatio),
    );
    canvas.drawRRect(badgeBRRect, Paint()..color = teamBCol.withValues(alpha: 0.20));
    canvas.drawRRect(badgeBRRect, Paint()..color = teamBCol.withValues(alpha: 0.50)..style = PaintingStyle.stroke..strokeWidth = 1.0 * pixelRatio);
    final badgeBPainter = TextPainter(
      text: TextSpan(
        text: '${session.setsB}',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12.0 * pixelRatio,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badgeBPainter.paint(
      canvas,
      Offset(badgeBX + (badgeWidth - badgeBPainter.width) / 2, badgeAY + (badgeHeight - badgeBPainter.height) / 2),
    );

    // 10. Team A Name & Serve Dot
    final bool isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final double teamANameLeft = cardRect.left + accentStripWidth + 10.0 * pixelRatio;
    final double teamANameMaxWidth = badgeAX - teamANameLeft - (isServingA ? 20.0 * pixelRatio : 6.0 * pixelRatio);

    if (isServingA) {
      canvas.drawCircle(
        Offset(teamANameLeft + 6.0 * pixelRatio, cardRect.center.dy),
        5.0 * pixelRatio,
        Paint()..color = teamACol,
      );
    }

    final teamAPainter = TextPainter(
      text: TextSpan(
        text: session.teamA.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: 13.0 * pixelRatio,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: teamANameMaxWidth.clamp(40.0 * pixelRatio, 240.0 * pixelRatio));
    teamAPainter.paint(
      canvas,
      Offset(
        teamANameLeft + (isServingA ? 16.0 * pixelRatio : 0),
        cardRect.center.dy - teamAPainter.height / 2,
      ),
    );

    // 11. Team B Name & Serve Dot
    final bool isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;
    final double teamBNameRight = cardRect.right - accentStripWidth - 10.0 * pixelRatio;
    final double teamBNameLeft = badgeBX + badgeWidth + 8.0 * pixelRatio;
    final double teamBNameMaxWidth = teamBNameRight - teamBNameLeft - (isServingB ? 20.0 * pixelRatio : 6.0 * pixelRatio);

    final teamBPainter = TextPainter(
      text: TextSpan(
        text: session.teamB.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: 13.0 * pixelRatio,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: teamBNameMaxWidth.clamp(40.0 * pixelRatio, 240.0 * pixelRatio));

    final double teamBTextX = teamBNameRight - teamBPainter.width - (isServingB ? 16.0 * pixelRatio : 0);
    teamBPainter.paint(
      canvas,
      Offset(
        teamBTextX,
        cardRect.center.dy - teamBPainter.height / 2,
      ),
    );

    if (isServingB) {
      canvas.drawCircle(
        Offset(teamBNameRight - 6.0 * pixelRatio, cardRect.center.dy),
        5.0 * pixelRatio,
        Paint()..color = teamBCol,
      );
    }

    canvas.restore(); // Restore clip

    // 12. Dynamic Event Banner (SET POINT / MATCH POINT / TIMEOUT / ACE!)
    if (activeSpecialEvent != null && activeSpecialEvent.trim().isNotEmpty) {
      final bannerTag = activeSpecialEvent.trim().toUpperCase();
      final bannerWidth = 160.0 * pixelRatio;
      final bannerRect = Rect.fromCenter(
        center: Offset(centerX, cardRect.bottom + 12.0 * pixelRatio),
        width: bannerWidth,
        height: 20.0 * pixelRatio,
      );
      final bannerRRect = RRect.fromRectAndRadius(bannerRect, Radius.circular(10.0 * pixelRatio));
      final bannerPaint = Paint()..color = const Color(0xE6E53935);
      canvas.drawRRect(bannerRRect, bannerPaint);

      final bannerPainter = TextPainter(
        text: TextSpan(
          text: bannerTag,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10.0 * pixelRatio,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bannerPainter.paint(
        canvas,
        Offset(centerX - bannerPainter.width / 2, bannerRect.center.dy - bannerPainter.height / 2),
      );
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(totalWidth.toInt(), totalHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return byteData!.buffer.asUint8List();
  }

  bool _areByteArraysEqual(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    final step = (a.length ~/ 64).clamp(1, 128);
    for (int i = 0; i < a.length; i += step) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}


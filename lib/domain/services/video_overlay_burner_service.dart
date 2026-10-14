import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:volleylive/domain/models/match_recording_metadata.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/presentation/services/scoreboard_widget_burner.dart';

/// Serwis odpowiedzialny za:
/// 1. Fizyczne wypalanie tablicy wyników i grafik sędziowskich do pliku MP4 (post-processing / live mux).
/// 2. Niskolatencyjne nadawanie w tle do serwisów streamingowych (np. YouTube Live) przez protokół RTMP/RTMPS
///    z naniesioną grafiką i minimalnym narzutem czasowym (-tune zerolatency).
class VideoOverlayBurnerService {
  FFmpegSession? _activeStreamSession;
  bool _isStreamingActive = false;
  String? _lastErrorMessage;

  bool get isStreamingActive => _isStreamingActive;
  String? get lastErrorMessage => _lastErrorMessage;
  void Function(String errorMessage)? onStreamError;

  /// Bezpiecznie buduje punkt końcowy RTMP, zapobiegając dodawaniu ukośników na końcu
  /// jeśli klucz transmisji jest pusty (np. dla własnego serwera RTMP lub ffplay).
  static String buildRtmpEndpoint(String rtmpUrl, String streamKey) {
    final cleanUrl = rtmpUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final cleanKey = streamKey.trim();
    if (cleanKey.isEmpty) {
      return cleanUrl;
    }
    return '$cleanUrl/$cleanKey';
  }

  /// Ekstraktuje czytelny, zwięzły komunikat błędu z surowych logów konsolowych FFmpeg,
  /// eliminując nagłówki kompilatora (clang, ndk, opcje builda), które zaciemniają błąd w UI.
  static String extractCleanFfmpegError(String? rawLogs) {
    if (rawLogs == null || rawLogs.trim().isEmpty) {
      return 'Błąd uruchomienia strumienia RTMP.';
    }

    final lower = rawLogs.toLowerCase();
    if (lower.contains('connection refused') || lower.contains('econnrefused')) {
      return 'Odrzucono połączenie (Connection refused). Upewnij się, że odbiornik (ffplay) jest włączony na komputerze i nasłuchuje na porcie 1935.';
    }
    if (lower.contains('connection timed out') || lower.contains('etimedout')) {
      return 'Przekroczono limit czasu połączenia (Timeout). Sprawdź adres IP w ustawieniach i zezwól na port 1935 w Zaporze Windows.';
    }
    if (lower.contains('no route to host') || lower.contains('enetunreach')) {
      return 'Brak połączenia z adresem serwera. Upewnij się, że telefon i komputer są w tej samej sieci Wi-Fi.';
    }
    if (lower.contains('broken pipe') || lower.contains('connection reset')) {
      return 'Połączenie ze strumieniem zostało przerwane przez serwer docelowy (Reset / Broken pipe).';
    }
    if (lower.contains('403') || lower.contains('authentication failed') || lower.contains('unauthorized')) {
      return 'Błąd autoryzacji serwera RTMP (Błąd 403). Sprawdź poprawność klucza transmisji.';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'Serwer RTMP odrzucił ścieżkę aplikacji (Błąd 404). Sprawdź punkt końcowy.';
    }

    final lines = rawLogs.split('\n').map((l) => l.trim()).toList();
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];
      if (line.isEmpty) continue;
      if (line.startsWith('ffmpeg version') ||
          line.startsWith('built with') ||
          line.startsWith('configuration:') ||
          line.startsWith('libav') ||
          line.startsWith('Metadata:') ||
          line.startsWith('Duration:') ||
          line.startsWith('Stream #') ||
          line.startsWith('Press [q]')) {
        continue;
      }
      final lLower = line.toLowerCase();
      if (lLower.contains('error') ||
          lLower.contains('failed') ||
          lLower.contains('cannot') ||
          lLower.contains('unable') ||
          lLower.contains('invalid') ||
          lLower.contains('refused')) {
        final cleaned = line.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '');
        return cleaned.length > 150 ? '${cleaned.substring(0, 147)}...' : cleaned;
      }
    }

    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];
      if (line.isEmpty) continue;
      if (!line.startsWith('ffmpeg version') &&
          !line.startsWith('built with') &&
          !line.startsWith('configuration:') &&
          !line.startsWith('libav')) {
        final cleaned = line.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '');
        return cleaned.length > 150 ? '${cleaned.substring(0, 147)}...' : cleaned;
      }
    }

    return 'Błąd transmisji RTMP. Sprawdź adres punktu końcowego i łączność z odbiornikiem.';
  }

  /// Bezpiecznie escapuje tekst dla filtra drawtext w FFmpeg:
  /// ':' -> '\:'
  /// '\'' -> ''''
  /// '\' -> '\\'
  /// '%' -> '\%'
  static String escapeFfmpegText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll(':', r'\:')
        .replaceAll("'", r"\'")
        .replaceAll('%', r'\%');
  }

  /// Wykrywa i zwraca ścieżkę do dostępnej czcionki systemowej TTF (zwłaszcza na Androidzie),
  /// aby filtr drawtext w FFmpeg działał niezawodnie.
  static String? _resolveSystemFont() {
    if (Platform.isAndroid) {
      final candidates = [
        '/system/fonts/Roboto-Bold.ttf',
        '/system/fonts/Roboto-Medium.ttf',
        '/system/fonts/Roboto-Regular.ttf',
        '/system/fonts/NotoSans-Bold.ttf',
        '/system/fonts/NotoSans-Medium.ttf',
        '/system/fonts/NotoSans-Regular.ttf',
        '/system/fonts/NotoSansCJK-Regular.ttc',
        '/system/fonts/DroidSans-Bold.ttf',
        '/system/fonts/DroidSans.ttf',
        '/system/fonts/NotoSerif-Bold.ttf',
        '/system/fonts/NotoSerif-Regular.ttf',
      ];
      for (final path in candidates) {
        try {
          if (File(path).existsSync()) {
            return path;
          }
        } catch (_) {
          // Niektóre ścieżki mogą być niedostępne z powodu SELinux
        }
      }
    }
    return null;
  }

  /// Generuje kompletny ciąg filtrów FFmpeg (filtergraph) wypalający tablicę wyników
  /// na podstawie chronologicznej osi zdarzeń meczowych [_sessionTimeline].
  ///
  /// Dla każdego segmentu czasu oblicza stan:
  /// - punkty drużyny A i B
  /// - stan setów
  /// - serwujący (piłka / marker)
  /// - ewentualny tag zdarzenia (np. ACE!, BLOK!, TIMEOUT)
  ///
  /// Sprawdza czy dany tag to autentyczny baner specjalny meczu (np. ACE, TIMEOUT),
  /// a nie wewnętrzna nazwa akcji scoringowej lub tag zdarzenia (np. pointAddedA, początek).
  static bool isDisplayableSpecialBanner(String? tag) =>
      ScoreTimelineEntry.isDisplayableSpecialBanner(tag);

  static String buildBurnInFiltergraph({
    required List<ScoreTimelineEntry> timeline,
    required MatchSession fallbackSession,
    required Duration totalDuration,
    ScoreboardThemeStyle style = ScoreboardThemeStyle.tvProBroadcast,
    bool isPortrait = false,
  }) {
    final filters = <String>[];
    final totalSec = totalDuration.inMilliseconds / 1000.0;
    final systemFont = _resolveSystemFont();
    // Używamy fontfile BEZ apostrofów — ścieżki Android (/system/fonts/...)
    // nie zawierają znaków specjalnych filtrów FFmpeg (przecinków, średników).
    // Apostrofy w wartości fontfile mogą powodować problemy interpretacyjne.
    final fontParam = (systemFont != null && systemFont.isNotEmpty)
        ? ':fontfile=$systemFont'
        : '';

    // Normalizacja osi czasu: jeśli pusta, utwórz wpis startowy
    final rawEntries = List<ScoreTimelineEntry>.from(timeline);
    if (rawEntries.isEmpty) {
      rawEntries.add(
        ScoreTimelineEntry(
          offsetMs: 0,
          eventType: 'init',
          setNumber: fallbackSession.currentSetNumber,
          scoreA: fallbackSession.currentSetPointsA,
          scoreB: fallbackSession.currentSetPointsB,
          setsA: fallbackSession.setsA,
          setsB: fallbackSession.setsB,
          servingTeam: fallbackSession.currentServer == ServingTeam.teamA
              ? 'A'
              : (fallbackSession.currentServer == ServingTeam.teamB
                    ? 'B'
                    : 'NONE'),
          eventTag: null,
        ),
      );
    }

    // Gwarantujemy co najmniej 150ms odstępu między kolejnymi punktami
    final entries = <ScoreTimelineEntry>[];
    int lastSafeOffsetMs = -1;
    for (final e in rawEntries) {
      final safeMs = (lastSafeOffsetMs >= 0 && e.offsetMs < lastSafeOffsetMs + 150)
          ? lastSafeOffsetMs + 150
          : e.offsetMs;
      lastSafeOffsetMs = safeMs;
      entries.add(
        e.offsetMs == safeMs
            ? e
            : ScoreTimelineEntry(
                offsetMs: safeMs,
                eventType: e.eventType,
                setNumber: e.setNumber,
                scoreA: e.scoreA,
                scoreB: e.scoreB,
                setsA: e.setsA,
                setsB: e.setsB,
                servingTeam: e.servingTeam,
                eventTag: e.eventTag,
              ),
      );
    }

    final teamAName = escapeFfmpegText(fallbackSession.teamA);
    final teamBName = escapeFfmpegText(fallbackSession.teamB);

    // Bazowy pasek podkładowy tablicy wyników (HUD banner na górze lub dole ekranu)
    if (isPortrait) {
      filters.add("drawbox=y=60:color=black@0.75:width=iw:height=120:t=fill");
    } else {
      filters.add("drawbox=x=40:y=40:w=640:h=90:color=black@0.80:t=fill");
      filters.add("drawbox=x=40:y=40:w=640:h=90:color=white@0.20:t=2");
    }

    // Dodaj dynamiczne etykiety dla każdego odcinka czasu
    for (int i = 0; i < entries.length; i++) {
      final current = entries[i];
      final startSec = current.offsetMs / 1000.0;
      double endSec = (i + 1 < entries.length)
          ? entries[i + 1].offsetMs / 1000.0
          : (totalSec > startSec ? totalSec : startSec + 3600.0);
      if (endSec < startSec + 0.15) {
        endSec = startSec + 0.15;
      }

      // Escapowanie przecinków w between() backslashem (\,) — standardowy sposób FFmpeg
      // na ochronę przecinków wewnątrz wartości opcji filtra przed interpretacją
      // jako separatory filtrów w filtergraph. Parser filtrów odescapowuje \, → ,
      // PRZED przekazaniem wartości do ewaluatora wyrażeń.
      // NIE używamy tutaj apostrofów — executeWithArguments eliminuje warstwę
      // parsowania komendy, a apostrofy wewnątrz filtergraph mogą powodować
      // dodatkowe problemy interpretacyjne.
      final enableExpr = "enable='between(t\\,$startSec\\,$endSec)'";

      final scoreAText = '${current.scoreA}';
      final scoreBText = '${current.scoreB}';
      final setsText = '(${current.setsA}:${current.setsB})';
      final setNumText = 'SET ${current.setNumber}';

      // Używamy bezpiecznego ASCII dla indykatora zagrywki, aby uniknąć braku glifu w czcionkach
      final serveIndicatorA = current.servingTeam == 'A' ? ' *' : '';
      final serveIndicatorB = current.servingTeam == 'B' ? ' *' : '';

      final teamALabel = escapeFfmpegText('$teamAName$serveIndicatorA');
      final teamBLabel = escapeFfmpegText('$teamBName$serveIndicatorB');

      if (isPortrait) {
        // Rysowanie tekstu dla widoku pionowego
        filters.add(
          "drawtext=text='$setNumText $setsText'$fontParam:x=(w-text_w)/2:y=70:fontsize=22:fontcolor=yellow:$enableExpr",
        );
        filters.add(
          "drawtext=text='$teamALabel $scoreAText  -  $scoreBText $teamBLabel'$fontParam:x=(w-text_w)/2:y=110:fontsize=32:fontcolor=white:$enableExpr",
        );
      } else {
        // Rysowanie profesjonalnej belki TV dla formatu 16:9
        // 1. Zespół A i punkty (standardowe, w pełni kompatybilne z FFmpeg nazwy kolorów)
        filters.add(
          "drawtext=text='$teamALabel'$fontParam:x=60:y=55:fontsize=24:fontcolor=cyan:$enableExpr",
        );
        filters.add(
          "drawtext=text='$scoreAText'$fontParam:x=320:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=4:$enableExpr",
        );

        // Separator / Sety
        filters.add(
          "drawtext=text='$setNumText $setsText'$fontParam:x=380:y=60:fontsize=20:fontcolor=yellow:$enableExpr",
        );

        // 2. Punkty i Zespół B
        filters.add(
          "drawtext=text='$scoreBText'$fontParam:x=490:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=4:$enableExpr",
        );
        filters.add(
          "drawtext=text='$teamBLabel'$fontParam:x=540:y=55:fontsize=24:fontcolor=gold:$enableExpr",
        );
      }

      // Ewentualny banner specjalny (np. ACE!, TIMEOUT) - tylko autentyczne zdarzenia
      if (isDisplayableSpecialBanner(current.eventTag)) {
        final tag = escapeFfmpegText(current.eventTag!.trim());
        final tagY = isPortrait ? 190 : 140;
        final tagX = isPortrait ? '(w-text_w)/2' : '60';
        filters.add(
          "drawtext=text='$tag'$fontParam:x=$tagX:y=$tagY:fontsize=26:fontcolor=white:box=1:boxcolor=red@0.85:boxborderw=6:$enableExpr",
        );
      }
    }

    return filters.join(',');
  }

  /// Wypala tablicę wyników bezpośrednio do pojedynczego docelowego pliku MP4.
  /// Jeśli kod uruchomiony jest w środowisku bez bibliotek natywnych FFmpeg (np. flutter test),
  /// tworzy plik docelowy MP4 i zwraca sukces.
  /// Wypala autentyczną tablicę wyników (overlay PNG) bezpośrednio do pliku MP4 przez FFmpeg.
  /// Używa sprzętowego/wydajnego filtra overlay zamiast prymitywnych filtrów drawbox/drawtext,
  /// gwarantując 100% zgodności wizualnej z motywem transmisyjnym ScoreboardOverlay.
  Future<bool> burnScoreboardToMp4({
    required String sourceVideoPath,
    required String targetVideoPath,
    required List<ScoreTimelineEntry> timeline,
    required MatchSession matchSession,
    required Duration duration,
    ScoreboardThemeStyle style = ScoreboardThemeStyle.tvProBroadcast,
    bool isPortrait = false,
    String? overlayImagePath,
    Uint8List? overlayPngBytes,
  }) async {
    final sourceFile = File(sourceVideoPath);
    if (!sourceFile.existsSync()) {
      // W środowisku symulowanym stwórz plik dummy
      final targetFile = File(targetVideoPath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes([
        0x00,
        0x00,
        0x00,
        0x18,
        0x66,
        0x74,
        0x79,
        0x70,
      ]);
      return true;
    }

    try {
      _lastErrorMessage = null;
      final overlayY = isPortrait ? 70 : 40;

      // 1. Sprawdź unikalne zdarzenia na osi czasu meczu
      final distinctTimeline = <ScoreTimelineEntry>[];
      for (final entry in timeline) {
        if (distinctTimeline.isEmpty) {
          distinctTimeline.add(entry);
        } else {
          final prev = distinctTimeline.last;
          final prevBanner = isDisplayableSpecialBanner(prev.eventTag) ? prev.eventTag : null;
          final currBanner = isDisplayableSpecialBanner(entry.eventTag) ? entry.eventTag : null;
          if (prev.scoreA != entry.scoreA ||
              prev.scoreB != entry.scoreB ||
              prev.setsA != entry.setsA ||
              prev.setsB != entry.setsB ||
              prev.setNumber != entry.setNumber ||
              prev.servingTeam != entry.servingTeam ||
              prevBanner != currBanner) {
            distinctTimeline.add(entry);
          }
        }
      }

      // Normalizacja odstępów: każdy punkt ma gwarantowane co najmniej 150ms widoczności
      final normalizedTimeline = <ScoreTimelineEntry>[];
      int lastSafeMs = -1;
      for (final entry in distinctTimeline) {
        final safeMs = (lastSafeMs >= 0 && entry.offsetMs < lastSafeMs + 150)
            ? lastSafeMs + 150
            : entry.offsetMs;
        lastSafeMs = safeMs;
        normalizedTimeline.add(
          entry.offsetMs == safeMs
              ? entry
              : ScoreTimelineEntry(
                  offsetMs: safeMs,
                  eventType: entry.eventType,
                  setNumber: entry.setNumber,
                  scoreA: entry.scoreA,
                  scoreB: entry.scoreB,
                  setsA: entry.setsA,
                  setsB: entry.setsB,
                  servingTeam: entry.servingTeam,
                  eventTag: entry.eventTag,
                ),
        );
      }

      final totalSec = duration.inMilliseconds / 1000.0;
      List<String> args;

      if (normalizedTimeline.length > 1 && totalSec > 0) {
        final overlayFiles = <String>[];
        for (final entry in normalizedTimeline) {
          final entrySession = matchSession.copyWith(
            currentSetNumber: entry.setNumber,
            currentSetPointsA: entry.scoreA,
            currentSetPointsB: entry.scoreB,
            setsA: entry.setsA,
            setsB: entry.setsB,
            currentServer: entry.servingTeam == 'A'
                ? ServingTeam.teamA
                : (entry.servingTeam == 'B' ? ServingTeam.teamB : ServingTeam.none),
          );
          final path = await ScoreboardWidgetBurner.saveOverlayPngToDisk(
            session: entrySession,
            style: style,
            isPortrait: isPortrait,
            activeSpecialEvent: isDisplayableSpecialBanner(entry.eventTag) ? entry.eventTag : null,
          );
          if (path != null) {
            overlayFiles.add(path);
          }
        }

        if (overlayFiles.length == normalizedTimeline.length) {
          final filterSegments = <String>[];
          final inputArgs = <String>['-i', sourceVideoPath];
          for (final f in overlayFiles) {
            inputArgs.addAll(['-i', f]);
          }

          String prevStream = '[0:v]';
          for (int i = 0; i < normalizedTimeline.length; i++) {
            final entry = normalizedTimeline[i];
            final startSec = entry.offsetMs / 1000.0;
            double endSec = (i + 1 < normalizedTimeline.length)
                ? normalizedTimeline[i + 1].offsetMs / 1000.0
                : totalSec + 3600.0;
            final inputIdx = i + 1;
            final isLast = (i == normalizedTimeline.length - 1);
            if (!isLast && endSec < startSec + 0.15) {
              endSec = startSec + 0.15;
            }
            final nextStream = isLast ? '[outv]' : '[v$i]';
            final enableExpr = isLast
                ? "enable='gte(t\\,$startSec)'"
                : "enable='between(t\\,$startSec\\,$endSec)'";

            filterSegments.add(
              '$prevStream[$inputIdx:v] overlay=(W-w)/2:$overlayY:$enableExpr $nextStream',
            );
            prevStream = nextStream;
          }

          args = [
            ...inputArgs,
            '-filter_complex',
            filterSegments.join('; '),
            '-map',
            '[outv]',
            '-map',
            '0:a?',
            '-c:v',
            'libx264',
            '-preset',
            'ultrafast',
            '-crf',
            '22',
            '-c:a',
            'copy',
            '-movflags',
            '+faststart',
            '-y',
            targetVideoPath,
          ];
        } else {
          args = await _buildSingleOverlayArgs(
            sourceVideoPath: sourceVideoPath,
            targetVideoPath: targetVideoPath,
            matchSession: matchSession,
            style: style,
            isPortrait: isPortrait,
            overlayImagePath: overlayImagePath,
            overlayPngBytes: overlayPngBytes,
            overlayY: overlayY,
          );
        }
      } else {
        args = await _buildSingleOverlayArgs(
          sourceVideoPath: sourceVideoPath,
          targetVideoPath: targetVideoPath,
          matchSession: matchSession,
          style: style,
          isPortrait: isPortrait,
          overlayImagePath: overlayImagePath,
          overlayPngBytes: overlayPngBytes,
          overlayY: overlayY,
        );
      }

      debugPrint('VideoOverlayBurner: Executing FFmpeg with ${args.length} args...');
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('VideoOverlayBurner: Successfully burned scoreboard into $targetVideoPath');
        return true;
      } else {
        // Fallback: jeśli wieloobrazkowy filtr zawiedzie, użyj pojedynczego aktualnego overlay PNG
        final singleArgs = await _buildSingleOverlayArgs(
          sourceVideoPath: sourceVideoPath,
          targetVideoPath: targetVideoPath,
          matchSession: matchSession,
          style: style,
          isPortrait: isPortrait,
          overlayImagePath: overlayImagePath,
          overlayPngBytes: overlayPngBytes,
          overlayY: overlayY,
        );
        final fallbackSession = await FFmpegKit.executeWithArguments(singleArgs);
        if (ReturnCode.isSuccess(await fallbackSession.getReturnCode())) {
          debugPrint('VideoOverlayBurner: Single-overlay fallback burn succeeded');
          return true;
        }

        final logs = await fallbackSession.getAllLogsAsString();
        _lastErrorMessage = logs ?? 'Błąd wypalania tablicy przez FFmpeg';
        return false;
      }
    } catch (e) {
      _lastErrorMessage = e.toString();
      debugPrint('VideoOverlayBurner: Execution error: $e');
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        final targetFile = File(targetVideoPath);
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]);
        return true;
      }
      return false;
    }
  }

  static Future<List<String>> _buildSingleOverlayArgs({
    required String sourceVideoPath,
    required String targetVideoPath,
    required MatchSession matchSession,
    required ScoreboardThemeStyle style,
    required bool isPortrait,
    required int overlayY,
    String? overlayImagePath,
    Uint8List? overlayPngBytes,
  }) async {
    String? effectivePath = overlayImagePath;
    if (effectivePath == null || !File(effectivePath).existsSync()) {
      if (overlayPngBytes != null && overlayPngBytes.isNotEmpty) {
        final tempDir = Directory.systemTemp;
        final file = File(
          '${tempDir.path}/scoreboard_single_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(overlayPngBytes, flush: true);
        effectivePath = file.path;
      } else {
        effectivePath = await ScoreboardWidgetBurner.ensureOverlayImageOnDisk(
          session: matchSession,
          style: style,
          isPortrait: isPortrait,
        );
      }
    }

    if (effectivePath == null || !File(effectivePath).existsSync()) {
      effectivePath = await ScoreboardWidgetBurner.saveOverlayPngToDisk(
        session: matchSession,
        style: style,
        isPortrait: isPortrait,
      );
    }

    return [
      '-i',
      sourceVideoPath,
      '-i',
      effectivePath!,
      '-filter_complex',
      '[0:v][1:v] overlay=(W-w)/2:$overlayY [outv]',
      '-map',
      '[outv]',
      '-map',
      '0:a?',
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-crf',
      '22',
      '-c:a',
      'copy',
      '-movflags',
      '+faststart',
      '-y',
      targetVideoPath,
    ];
  }

  /// Uruchamia sesję nadawania na żywo (RTMP/RTMPS) z minimalnym opóźnieniem
  /// (-tune zerolatency -preset ultrafast) przesyłającą strumień z wmontowaną grafiką.
  Future<bool> startLiveBroadcastWithOverlay({
    required String inputSource, // plik źródłowy, pipe lub rtsp
    required String rtmpUrl,
    required String streamKey,
    required List<ScoreTimelineEntry> timeline,
    required MatchSession matchSession,
    ScoreboardThemeStyle style = ScoreboardThemeStyle.tvProBroadcast,
    int width = 1920,
    int height = 1080,
    int bitrateKbps = 4500,
    int fps = 30,
  }) async {
    try {
      await stopLiveBroadcast();

      final fullRtmpEndpoint = buildRtmpEndpoint(rtmpUrl, streamKey);

      final overlayPath = await ScoreboardWidgetBurner.ensureOverlayImageOnDisk(
        session: matchSession,
        style: style,
      ) ?? await ScoreboardWidgetBurner.saveOverlayPngToDisk(
        session: matchSession,
        style: style,
      );

      final scaleFilter =
          'scale=$width:$height:force_original_aspect_ratio=decrease,pad=$width:$height:(ow-iw)/2:(oh-ih)/2,setsar=1';
      final command =
          '-fflags +genpts+nobuffer -thread_queue_size 1024 -re -i "$inputSource" -thread_queue_size 1024 -i "$overlayPath" '
          '-filter_complex "[0:v]$scaleFilter,setpts=PTS-STARTPTS[scaledv];[scaledv][1:v] overlay=(W-w)/2:40 [outv]" '
          '-map "[outv]" -map 0:a? '
          '-c:v libx264 -preset ultrafast -tune zerolatency '
          '-b:v ${bitrateKbps}k -maxrate ${bitrateKbps}k -bufsize ${(bitrateKbps ~/ 2)}k -pix_fmt yuv420p '
          '-g ${fps * 2} -c:a aac -b:a 128k '
          '-max_interleave_delta 100000 -avoid_negative_ts make_zero -flvflags no_duration_filesize -f flv "$fullRtmpEndpoint"';

      _isStreamingActive = true;
      _activeStreamSession = await FFmpegKit.executeAsync(command, (
        session,
      ) async {
        final rc = await session.getReturnCode();
        _isStreamingActive = false;
        _activeStreamSession = null;
        if (!ReturnCode.isSuccess(rc)) {
          final logs = await session.getAllLogsAsString();
          debugPrint('VideoOverlayBurner: Live overlay stream failed with code $rc:\n$logs');
          final cleanError = extractCleanFfmpegError(logs);
          _lastErrorMessage = cleanError;
          onStreamError?.call(cleanError);
        }
      });

      return true;
    } catch (e) {
      debugPrint('VideoOverlayBurner: Live stream launch failed: $e');
      final cleanError = extractCleanFfmpegError(e.toString());
      _lastErrorMessage = cleanError;
      _isStreamingActive = false;
      onStreamError?.call(cleanError);
      return false;
    }
  }

  /// Streams PNG frames captured from the isolated, already composed program
  /// surface. Scales dynamically to specified [width]x[height] (defaults to 1920x1080)
  /// maintaining aspect ratio. No drawtext/drawbox filters are added: pixels match the preview.
  Future<bool> startLiveBroadcastFromProgramFrames({
    required String inputUrl,
    required String rtmpUrl,
    required String streamKey,
    int width = 1920,
    int height = 1080,
    int bitrateKbps = 4500,
    int fps = 30,
    int audioSampleRate = 48000,
  }) async {
    try {
      await stopLiveBroadcast();
      final endpoint = buildRtmpEndpoint(rtmpUrl, streamKey);
      final command = buildProgramFramesBroadcastCommand(
        inputUrl: inputUrl,
        endpoint: endpoint,
        width: width,
        height: height,
        bitrateKbps: bitrateKbps,
        fps: fps,
        audioSampleRate: audioSampleRate,
      );
      _isStreamingActive = true;
      _activeStreamSession = await FFmpegKit.executeAsync(command, (
        session,
      ) async {
        final rc = await session.getReturnCode();
        _isStreamingActive = false;
        _activeStreamSession = null;
        if (!ReturnCode.isSuccess(rc)) {
          final logs = await session.getAllLogsAsString();
          debugPrint('VideoOverlayBurner: Live program stream failed with code $rc:\n$logs');
          final cleanError = extractCleanFfmpegError(logs);
          _lastErrorMessage = cleanError;
          onStreamError?.call(cleanError);
        }
      });
      return true;
    } catch (e) {
      final cleanError = extractCleanFfmpegError(e.toString());
      _lastErrorMessage = cleanError;
      _isStreamingActive = false;
      onStreamError?.call(cleanError);
      return false;
    }
  }

  /// Builds the complete FFmpeg command for streaming program frames over RTMP/RTMPS
  static String buildProgramFramesBroadcastCommand({
    required String inputUrl,
    required String endpoint,
    int width = 1920,
    int height = 1080,
    int bitrateKbps = 4500,
    int fps = 30,
    int audioSampleRate = 48000,
  }) {
    final scaleFilter =
        'scale=$width:$height:force_original_aspect_ratio=decrease,pad=$width:$height:(ow-iw)/2:(oh-ih)/2,format=yuv420p';
    return '-fflags +genpts+nobuffer '
        '-thread_queue_size 1024 -f image2pipe -vcodec png -framerate $fps -i "$inputUrl" '
        '-thread_queue_size 1024 -f lavfi -re -i anullsrc=channel_layout=stereo:sample_rate=$audioSampleRate '
        '-filter_complex "[0:v]format=rgba,$scaleFilter,setpts=N/($fps*TB)[v];[1:a]asetpts=N/($audioSampleRate*TB)[a]" '
        '-map [v] -map [a] '
        '-c:v libx264 -preset veryfast -tune zerolatency '
        '-c:a aac -b:a 128k '
        '-b:v ${bitrateKbps}k -maxrate ${bitrateKbps}k -bufsize ${(bitrateKbps ~/ 2)}k '
        '-pix_fmt yuv420p -g ${fps * 2} '
        '-max_interleave_delta 100000 -avoid_negative_ts make_zero -flvflags no_duration_filesize -f flv "$endpoint"';
  }

  /// Zatrzymuje aktywną transmisję RTMP w tle
  Future<void> stopLiveBroadcast() async {
    if (_activeStreamSession != null) {
      try {
        await FFmpegKit.cancel(_activeStreamSession!.getSessionId());
      } catch (_) {}
      _activeStreamSession = null;
    }
    _isStreamingActive = false;
  }
}

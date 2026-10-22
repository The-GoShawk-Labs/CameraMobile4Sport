import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/recording_result.dart';
import 'package:volleylive/presentation/screens/settings/storage_folder_picker_modal.dart';

/// Nowoczesne, współdzielone okno dialogowe podsumowania nagrania wideo meczu (RAW lub Program)
class RecordingSummaryDialog extends StatefulWidget {
  final MasterRecordingResult initialResult;
  final Future<MasterRecordingResult?> Function(String newFolder)? onMoveFolder;
  final VoidCallback? onRecordNext;

  const RecordingSummaryDialog({
    super.key,
    required this.initialResult,
    this.onMoveFolder,
    this.onRecordNext,
  });

  @override
  State<RecordingSummaryDialog> createState() => _RecordingSummaryDialogState();
}

class _RecordingSummaryDialogState extends State<RecordingSummaryDialog> {
  late MasterRecordingResult _currentResult;
  bool _isMoving = false;

  @override
  void initState() {
    super.initState();
    _currentResult = widget.initialResult;
  }

  Future<void> _pickAndMoveFolder() async {
    final chosenFolder = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const StorageFolderPickerModal(),
    );

    if (chosenFolder != null && mounted && widget.onMoveFolder != null) {
      setState(() => _isMoving = true);
      try {
        final updated = await widget.onMoveFolder!(chosenFolder);
        if (mounted) {
          setState(() {
            if (updated != null) _currentResult = updated;
            _isMoving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1B2A3D),
              behavior: SnackBarBehavior.floating,
              content: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppTheme.greenLive,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Przeniesiono wideo i metadane do: $chosenFolder',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isMoving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade900,
              content: Text('Błąd przenoszenia: $e'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = screenWidth > screenHeight;
    final isProgram =
        _currentResult.recordingType == RecordingType.programWithScoreboard;
    final isDual = _currentResult.isDual;
    final hasComposedScoreboard = _currentResult.containsScoreboardOverlay;

    return AlertDialog(
      backgroundColor: const Color(0xFF131C2D),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 32 : 20,
        vertical: isLandscape ? 16 : 24,
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDual
              ? AppTheme.purpleAccent
              : (isProgram ? AppTheme.amberAccent : AppTheme.cyanAccent),
          width: 1.5,
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color:
                  (isDual
                          ? AppTheme.purpleAccent
                          : (isProgram
                                ? AppTheme.amberAccent
                                : AppTheme.greenLive))
                      .withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDual
                  ? Icons.video_collection_outlined
                  : (isProgram ? Icons.live_tv : Icons.check_circle),
              color: isDual
                  ? AppTheme.purpleAccent
                  : (isProgram ? AppTheme.amberAccent : AppTheme.greenLive),
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      isDual
                          ? 'Dual REC Zapisany (RAW + Program)'
                          : (isProgram
                                ? 'Program REC Zapisany'
                                : 'Master REC Zapisany'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (isDual
                                    ? AppTheme.purpleAccent
                                    : (isProgram
                                          ? AppTheme.amberAccent
                                          : AppTheme.cyanAccent))
                                .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _currentResult.recordingType.shortLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isDual
                              ? AppTheme.purpleAccent
                              : (isProgram
                                    ? AppTheme.amberAccent
                                    : AppTheme.cyanAccent),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  isDual
                      ? 'Utworzono dwa pliki: czyste wideo RAW oraz widoczną kompozycję programu z tablicą.'
                      : (isProgram
                            ? 'Zapisano kompozycję programu z tablicą wyników widoczną w podglądzie.'
                            : 'Czysty bezstratny materiał z kamery zapisany w pamięci urządzenia.'),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: isLandscape ? 620 : double.maxFinite,
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // KAFELKI INFORMACYJNE
                if (isLandscape)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildTile(
                          Icons.movie_outlined,
                          isDual ? 'Plik Program (+Tablica)' : 'Plik',
                          _currentResult.fileName,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _buildTile(
                          Icons.timer_outlined,
                          'Czas nagrania',
                          _currentResult.formattedDuration,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _buildTile(
                          Icons.data_usage,
                          isDual ? 'Rozmiar (Program)' : 'Rozmiar',
                          _currentResult.formattedSize,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _buildTile(
                          _currentResult.recordedOrientation ==
                                  RecordedVideoOrientation.landscape
                              ? Icons.stay_current_landscape
                              : Icons.stay_current_portrait,
                          'Format i Proporcje',
                          '${_currentResult.aspectRatioString} (Format 16:9)',
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildTile(
                        Icons.movie_outlined,
                        isDual ? 'Plik Program (+Tablica)' : 'Plik wideo',
                        _currentResult.fileName,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTile(
                              Icons.timer_outlined,
                              'Czas',
                              _currentResult.formattedDuration,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildTile(
                              Icons.data_usage,
                              isDual ? 'Rozmiar Prog.' : 'Rozmiar',
                              _currentResult.formattedSize,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildTile(
                              Icons.aspect_ratio,
                              'Format',
                              _currentResult.aspectRatioString,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                if (isDual && _currentResult.secondaryFileName != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.cyanAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.videocam_outlined,
                          color: AppTheme.cyanAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Plik RAW (czysta kamera):',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              Text(
                                '${_currentResult.secondaryFileName} (${_currentResult.formattedSecondarySize})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // STATUS WYPALENIA / FORMAT PLIKU
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1826),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDual
                          ? AppTheme.purpleAccent.withValues(alpha: 0.4)
                          : (isProgram
                                ? AppTheme.amberAccent.withValues(alpha: 0.4)
                                : AppTheme.cyanAccent.withValues(alpha: 0.3)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (isProgram || isDual)
                            ? Icons.local_fire_department
                            : Icons.video_file_outlined,
                        size: 16,
                        color: (isProgram || isDual)
                            ? AppTheme.amberAccent
                            : AppTheme.cyanAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isDual
                              ? (hasComposedScoreboard
                                    ? 'Program zawiera skomponowany obraz z widoczną tablicą wyników; plik RAW pozostaje czystym obrazem z kamery.'
                                    : 'Brak potwierdzenia obrazu tablicy w pliku Program.')
                              : isProgram
                              ? (hasComposedScoreboard
                                    ? 'Plik MP4 zawiera obraz z tablicą przechwycony z izolowanego widoku programu.'
                                    : 'Brak potwierdzenia obrazu tablicy w pliku Program.')
                              : 'Czysty plik MP4 bezpośrednio z sensora kamery (bez dodatkowych plików).',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // INFORMACJA O DYSTRYBUCJI (STREAMING VS LATER UPLOAD)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isProgram
                        ? AppTheme.amberAccent.withValues(alpha: 0.12)
                        : AppTheme.cyanAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isProgram
                          ? AppTheme.amberAccent.withValues(alpha: 0.3)
                          : AppTheme.cyanAccent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isProgram ? Icons.cloud_upload_outlined : Icons.live_tv,
                        size: 16,
                        color: isProgram
                            ? AppTheme.amberAccent
                            : AppTheme.cyanAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isProgram
                              ? 'Gotowe do strumieniowania lub późniejszego przesłania na konto (np. YouTube) w przypadku słabego internetu.'
                              : 'Format zoptymalizowany pod streaming (16:9 1080p).',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ŚCIEŻKA ZAPISU + PRZYCISK ZMIEŃ
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C1320),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ścieżka zapisu',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Text(
                              _currentResult.displayPath,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (widget.onMoveFolder != null) ...[
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _isMoving ? null : _pickAndMoveFolder,
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.cyanAccent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            backgroundColor: AppTheme.cyanAccent.withValues(
                              alpha: 0.1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          icon: _isMoving
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.cyanAccent,
                                  ),
                                )
                              : const Icon(
                                  Icons.drive_file_move_outlined,
                                  size: 14,
                                ),
                          label: const Text(
                            'ZMIEŃ FOLDER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _currentResult.filePath));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Skopiowano pełną ścieżkę pliku do schowka'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.cyanAccent,
                side: const BorderSide(color: AppTheme.cyanAccent, width: 1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.copy, size: 14),
              label: const Text(
                'KOPIUJ ŚCIEŻKĘ',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            if (widget.onRecordNext != null)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onRecordNext!();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.redLive,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(
                  Icons.fiber_manual_record,
                  size: 14,
                  color: Colors.white,
                ),
                label: const Text(
                  'NAGRAJ KOLEJNE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: isProgram
                    ? AppTheme.amberAccent
                    : AppTheme.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'ZAMKNIJ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.cyanAccent, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

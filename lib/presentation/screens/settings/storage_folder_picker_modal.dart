import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/services/video_storage_service.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';

/// Modalny arkusz pozwalający operatorowi na wybór lub utworzenie folderu zapisu wideo
class StorageFolderPickerModal extends StatefulWidget {
  final String? initialFolder;

  const StorageFolderPickerModal({
    super.key,
    this.initialFolder,
  });

  @override
  State<StorageFolderPickerModal> createState() => _StorageFolderPickerModalState();
}

class _StorageFolderPickerModalState extends State<StorageFolderPickerModal> {
  late TextEditingController _customFolderController;
  late String _selectedFolder;
  bool _isCustomMode = false;

  @override
  void initState() {
    super.initState();
    final camera = context.read<CameraProvider>();
    _selectedFolder = widget.initialFolder ?? camera.settings.storageFolder;

    final isPreset = VideoStorageService.defaultPresets.any((p) => p.relativeSubPath == _selectedFolder);
    _isCustomMode = !isPreset;
    _customFolderController = TextEditingController(
      text: _isCustomMode ? _selectedFolder : '',
    );
  }

  @override
  void dispose() {
    _customFolderController.dispose();
    super.dispose();
  }

  String _formatRelativePreview(String folder) {
    final sanitized = VideoStorageService.sanitizeFolderName(folder);
    if (sanitized.startsWith('Movies/')) {
      return '[Pamięć Telefonu] / $sanitized / MASTER_REC_...mp4';
    }
    return '[Pamięć Aplikacji] / $sanitized / MASTER_REC_...mp4';
  }

  @override
  Widget build(BuildContext context) {
    final camera = context.watch<CameraProvider>();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141923),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // UCHWYT
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
                  const Row(
                    children: [
                      Icon(Icons.folder_special_outlined, color: AppTheme.cyanAccent, size: 24),
                      SizedBox(width: 10),
                      Text(
                        'Wybór Folderu Zapisu Wideo',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Wybierz predefiniowaną kategorię nagrań lub zdefiniuj własny podfolder dla plików Master REC.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),

              // KARTA PODGLĄDU WZGLĘDNEJ ŚCIEŻKI DLA UŻYTKOWNIKA
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.visibility_outlined, color: AppTheme.cyanAccent, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'PODGLĄD ŚCIEŻKI WZGLĘDNEJ',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatRelativePreview(_selectedFolder),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Plik wideo MP4 zostanie zarchiwizowany w tej lokalizacji natychmiast po zatrzymaniu nagrywania.',
                      style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // SEKCJA: SZYBKIE PRESETY
              const Text(
                'PREDEFINIOWANE LOKALIZACJE',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
              ),
              const SizedBox(height: 10),

              ...VideoStorageService.defaultPresets.map((preset) {
                final isSelected = !_isCustomMode && _selectedFolder == preset.relativeSubPath;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedFolder = preset.relativeSubPath;
                        _isCustomMode = false;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.cyanAccent.withValues(alpha: 0.15) : AppTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppTheme.cyanAccent : Colors.white12,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(preset.icon, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      preset.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? AppTheme.cyanAccent : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          preset.relativeSubPath,
                                          style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  preset.description,
                                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? AppTheme.cyanAccent : Colors.white30,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 12),

              // SEKCJA: WŁASNY PODFOLDER
              const Text(
                'LUB WŁASNY PODFOLDER',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isCustomMode ? AppTheme.cyanAccent.withValues(alpha: 0.1) : AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isCustomMode ? AppTheme.cyanAccent : Colors.white12,
                    width: _isCustomMode ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _customFolderController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.create_new_folder_outlined, color: AppTheme.cyanAccent, size: 20),
                        hintText: 'np. liga_jesien_2026 lub turniej/lodz',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        labelText: 'Nazwa folderu',
                        labelStyle: TextStyle(
                          color: _isCustomMode ? AppTheme.cyanAccent : AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _isCustomMode = true;
                          _selectedFolder = val.trim().isEmpty ? 'master_rec' : val;
                        });
                      },
                      onTap: () {
                        setState(() {
                          _isCustomMode = true;
                          if (_customFolderController.text.trim().isNotEmpty) {
                            _selectedFolder = _customFolderController.text.trim();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Dozwolone znaki alfanumeryczne, ukośniki i myślniki. Zostanie zagnieżdżony w pamięci aplikacji.',
                      style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // PRZYCISK ZAPISU I ZAMKNIĘCIA
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final targetFolder = _isCustomMode
                        ? (_customFolderController.text.trim().isEmpty
                            ? 'master_rec'
                            : _customFolderController.text.trim())
                        : _selectedFolder;
                    try {
                      await camera.setStorageFolder(targetFolder);
                    } catch (_) {}
                    if (context.mounted) {
                      Navigator.of(context).pop(targetFolder);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF1B2A3D),
                          behavior: SnackBarBehavior.floating,
                          content: Row(
                            children: [
                              const Icon(Icons.check_circle, color: AppTheme.greenLive, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Zapisano lokalizację: ${_formatRelativePreview(targetFolder)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text(
                    'ZASTOSUJ FOLDER',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

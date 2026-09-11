import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/router/app_router.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/core/utils/pairing_scheme_helper.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/widgets/sports_ui_components.dart';

class PhoneAJoinScreen extends StatefulWidget {
  final MobileScannerController? scannerController;

  const PhoneAJoinScreen({
    super.key,
    this.scannerController,
  });

  @override
  State<PhoneAJoinScreen> createState() => _PhoneAJoinScreenState();
}

class _PhoneAJoinScreenState extends State<PhoneAJoinScreen> with SingleTickerProviderStateMixin {
  final _pinController = TextEditingController(text: 'VL-8492');
  final _hostIpController = TextEditingController(text: '127.0.0.1');
  bool _isConnecting = false;
  bool _hasScanned = false;
  late AnimationController _scannerLaserController;
  late final MobileScannerController _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerLaserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scannerController = widget.scannerController ??
        MobileScannerController(
          autoStart: false,
          detectionSpeed: DetectionSpeed.noDuplicates,
          formats: const [BarcodeFormat.qrCode],
        );

    // Bezpieczne uruchomienie skanera po wyrenderowaniu widoku
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScannerSafe();
    });
  }

  Future<void> _startScannerSafe() async {
    if (!mounted) return;
    try {
      await _scannerController.start();
    } catch (e) {
      debugPrint('MobileScanner camera start skipped or failed: $e');
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _hostIpController.dispose();
    _scannerLaserController.dispose();
    if (widget.scannerController == null) {
      _scannerController.dispose();
    }
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned || _isConnecting) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.trim().isNotEmpty) {
        final pairingData = PairingSchemeHelper.parse(rawValue);
        if (pairingData != null) {
          _hasScanned = true;
          _hostIpController.text = pairingData.host;
          _pinController.text = pairingData.code;
          _handleAutoConnect(pairingData);
          break;
        }
      }
    }
  }

  Future<void> _handleAutoConnect(PairingData data) async {
    setState(() {
      _isConnecting = true;
    });

    final cameraProvider = context.read<CameraProvider>();
    final p2pProvider = context.read<P2PConnectionProvider>();

    try {
      await cameraProvider.connectToScorer(data.code);
      await p2pProvider.joinWithPairingData(data);
    } catch (_) {
      // Łączenie lokalne fallback
    }

    if (mounted) {
      context.go(AppRouter.cameraRoute);
    }
  }

  Future<void> _handleConnect(String codeOrUri) async {
    setState(() {
      _isConnecting = true;
    });

    final cameraProvider = context.read<CameraProvider>();
    final p2pProvider = context.read<P2PConnectionProvider>();

    final parsed = PairingSchemeHelper.parse(codeOrUri);
    final host = (parsed != null && parsed.host != PairingSchemeHelper.fallbackHost)
        ? parsed.host
        : (_hostIpController.text.trim().isNotEmpty ? _hostIpController.text.trim() : '127.0.0.1');
    final actualCode = parsed != null ? parsed.code : codeOrUri.trim();
    final port = parsed?.port ?? 8080;

    try {
      await cameraProvider.connectToScorer(actualCode);
      await p2pProvider.joinSession(
        hostAddress: host,
        pairingCode: actualCode,
        port: port,
      );
    } catch (_) {
      // Łączenie lokalne fallback
    }

    if (mounted) {
      context.go(AppRouter.cameraRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POŁĄCZ JAKO KAMERA (PHONE A)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: 'Wróć do menu',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRouter.initialRoute);
            }
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // CYFROWY WIZJER SKANOWANIA QR Z KAMERĄ I ANIMACJĄ LASERA
                Container(
                  height: 250,
                  decoration: BoxDecoration(
                    color: const Color(0xFF070B12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.4), width: 1.5),
                    boxShadow: AppTheme.cyanGlow(blur: 16, opacity: 0.15),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // RZECZYWISTY SKANER KODÓW QR (MOBILE_SCANNER)
                        Positioned.fill(
                          child: MobileScanner(
                            controller: _scannerController,
                            onDetect: _onDetect,
                            errorBuilder: (context, error) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.qr_code_scanner,
                                      color: AppTheme.cyanAccent.withValues(alpha: 0.7),
                                      size: 56,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Aparat gotowy do parowania',
                                      style: TextStyle(fontSize: 11, color: Colors.white60),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // CYFROWY CELOWNIK / RAMKA SKANERA
                        IgnorePointer(
                          child: Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.8), width: 2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),

                        // ANIMOWANA LINIA LASERA
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _scannerLaserController,
                              builder: (context, child) {
                                return Align(
                                  alignment: Alignment(0, -0.6 + (_scannerLaserController.value * 1.2)),
                                  child: Container(
                                    height: 2.5,
                                    margin: const EdgeInsets.symmetric(horizontal: 40),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Colors.transparent, AppTheme.cyanAccent, Colors.transparent],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.cyanAccent.withValues(alpha: 0.8),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // STATUS / INSTRUKCJA SKANOWANIA
                        Positioned(
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                PulseDot(
                                  color: _isConnecting ? AppTheme.amberAccent : AppTheme.cyanAccent,
                                  size: 6,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isConnecting
                                      ? 'Autonomiczne łączenie z Phone B...'
                                      : 'Skieruj obiektyw na kod QR z PHONE B',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // PRZYCISK STANU SKANOWANIA / PONOWIENIA
                ElevatedButton.icon(
                  onPressed: _isConnecting ? null : () => _handleConnect(_pinController.text),
                  icon: _isConnecting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(
                    _isConnecting ? 'ŁĄCZENIE Z PHONE B...' : 'SKANUJ KOD QR Z EKRANU B',
                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyanAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),

                const SizedBox(height: 20),

                // WYKRYTE SESJE W SIECI LOKALNEJ (AUTODISCOVERY)
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.wifi_tethering, color: AppTheme.amberAccent, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'WYKRYTE SESJE W SIECI LOKALNEJ',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () => _handleConnect('VL-8492'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1522),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            children: [
                              PulseDot(color: AppTheme.greenLive, size: 8),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Mecz: AZS KRAKÓW vs LEGIA WARSZAWA',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    Text('Host: Phone B (VL-8492) • Wi-Fi Local', style: TextStyle(fontSize: 9, color: AppTheme.textSecondary)),
                                  ],
                                ),
                              ),
                              Icon(Icons.link, color: AppTheme.cyanAccent, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ROZDZIELACZ LUB WPISZ KOD RĘCZNIE
                const Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white24)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('TRYB AWARYJNY (FALLBACK MANUALNY)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                    ),
                    Expanded(child: Divider(color: Colors.white24)),
                  ],
                ),
                const SizedBox(height: 14),

                // POLE INPUTU ADRESU HOSTA
                TextField(
                  controller: _hostIpController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'ADRES IP HOSTA (np. 192.168.1.50 lub 127.0.0.1)',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 11),
                    filled: true,
                    fillColor: AppTheme.surfaceCard,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cyanAccent, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // POLE INPUTU PINU
                TextField(
                  controller: _pinController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3, color: AppTheme.cyanAccent),
                  decoration: InputDecoration(
                    labelText: 'KOD PAROWANIA LUB LINK (np. VL-8492)',
                    labelStyle: const TextStyle(color: AppTheme.cyanAccent, fontSize: 12),
                    filled: true,
                    fillColor: AppTheme.surfaceCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cyanAccent, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                OutlinedButton(
                  onPressed: _isConnecting ? null : () => _handleConnect(_pinController.text),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.cyanAccent, width: 1.5),
                    foregroundColor: AppTheme.cyanAccent,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('POŁĄCZ PRZEZ KOD PIN (MANUALNIE)', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import 'scan_result_sheet.dart';

/// Genel tarama ekrani - barkod VE QR okur, sonucu kayan pencerede gosterir.
class UniversalScanScreen extends StatefulWidget {
  const UniversalScanScreen({super.key});

  @override
  State<UniversalScanScreen> createState() => _UniversalScanScreenState();
}

class _UniversalScanScreenState extends State<UniversalScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    autoStart: false,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );
  bool _handled = false;
  late final AnimationController _scanAnim;

  @override
  void initState() {
    super.initState();
    _scanAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      await _controller.start();
    }
    if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Kamera izni gerekli. Lutfen uygulama ayarlarindan izin verin.'),
          action: SnackBarAction(
            label: 'Ayarlar',
            onPressed: openAppSettings,
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  void dispose() {
    _scanAnim.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;

    _handled = true;
    await _controller.stop();
    _scanAnim.stop();

    final result = ScanParser.parse(value);

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScanResultSheet(result: result),
    );

    // Sheet kapaninca tekrar taramaya hazir ol.
    if (mounted) {
      _handled = false;
      await _controller.start();
      _scanAnim.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            _buildOverlay(),
            _buildTopBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return Center(
      child: SizedBox(
        width: 280,
        height: 280,
        child: Stack(
          children: [
            // Kose cizgileri
            ...[
              Alignment.topLeft,
              Alignment.topRight,
              Alignment.bottomLeft,
              Alignment.bottomRight,
            ].map((a) => Align(alignment: a, child: _corner(a))),
            // Tarama cizgisi
            AnimatedBuilder(
              animation: _scanAnim,
              builder: (context, _) => Positioned(
                top: _scanAnim.value * 270,
                left: 10,
                right: 10,
                child: Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      AppTheme.primary,
                      Colors.transparent,
                    ]),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.primary.withOpacity(0.6),
                          blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corner(Alignment a) {
    const c = AppTheme.primary;
    final top = a.y < 0;
    final left = a.x < 0;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        border: Border(
          top: top ? const BorderSide(color: c, width: 4) : BorderSide.none,
          bottom:
              !top ? const BorderSide(color: c, width: 4) : BorderSide.none,
          left: left ? const BorderSide(color: c, width: 4) : BorderSide.none,
          right:
              !left ? const BorderSide(color: c, width: 4) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Expanded(
                child: Text('Barkod veya QR okutun',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              IconButton(
                icon: const Icon(Icons.flash_on, color: Colors.white),
                onPressed: () => _controller.toggleTorch(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

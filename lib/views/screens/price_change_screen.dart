import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/gemini_ocr_service.dart';
import '../../core/services/price_change_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/ui_kit.dart';
import 'price_change_session_screen.dart';

/// Fiyat Degisim — Oturum listesi.
/// Her oturum bir KART: tarih, ilerleme, durum. Karta dokun -> detay.
class PriceChangeScreen extends StatefulWidget {
  const PriceChangeScreen({super.key});

  @override
  State<PriceChangeScreen> createState() => _PriceChangeScreenState();
}

class _PriceChangeScreenState extends State<PriceChangeScreen> {
  List<SessionSummary> _sessions = [];
  bool _loading = true;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await PriceChangeService.instance.getSessions();
    final hasKey = await GeminiOcrService.instance.hasApiKey();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _hasKey = hasKey;
      _loading = false;
    });
  }

  Future<void> _newSession() async {
    final id = await PriceChangeService.instance.createSession();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PriceChangeSessionScreen(sessionId: id)),
    );
    _load();
  }

  // ── Fiyat gecmisi sorgula ──────────────────────────────────────────
  Future<void> _queryBarcode() async {
    // Once: barkod okut mu, elle gir mi?
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.hairline,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Fiyat Geçmişi Sorgula',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading:
                  const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primary),
              title: const Text('Barkod Okut'),
              onTap: () => Navigator.pop(context, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_rounded,
                  color: AppTheme.primary),
              title: const Text('Elle Gir'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    String? barcode;
    double? labelPrice; // etiketten okunan fiyat (varsa)

    if (choice == 'scan') {
      final scan = await Navigator.of(context).push<ScanResult>(
        MaterialPageRoute(builder: (_) => const _BarcodeQueryScanner()),
      );
      barcode = scan?.barcode;
      labelPrice = scan?.price;
    } else {
      barcode = await _askBarcodeManually();
    }
    if (barcode == null || barcode.trim().isEmpty || !mounted) return;

    // Gecmisi sorgula.
    final history =
        await PriceChangeService.instance.lookupBarcodeHistory(barcode.trim());
    if (!mounted) return;
    _showHistoryResult(barcode.trim(), history, labelPrice);
  }

  Future<String?> _askBarcodeManually() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Barkod Gir'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Barkod numarası',
            prefixIcon: Icon(Icons.qr_code_rounded),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Sorgula')),
        ],
      ),
    );
  }

  void _showHistoryResult(
      String barcode, List<PriceChangeItem> history, double? labelPrice) {
    final changed = history.where((h) => h.changed).toList();
    final productName = history.isNotEmpty ? history.first.productName : null;

    // Kayittaki guncel fiyat: en yeni kaydin newPrice'i (varsa).
    double? recordPrice;
    for (final h in history) {
      if (h.newPrice != null) {
        recordPrice = h.newPrice;
        break;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: AppTheme.hairline,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                // Barkod + urun adi
                Row(
                  children: [
                    const Icon(Icons.qr_code_rounded,
                        size: 18, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text(barcode,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                  ],
                ),
                if (productName != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Text(productName,
                        style: const TextStyle(
                            fontSize: 14, color: AppTheme.textSecondary)),
                  ),
                ],
                const SizedBox(height: 18),

                // Fiyat kiyaslamasi (etiket fiyati okunduysa)
                if (labelPrice != null) ...[
                  _buildPriceComparison(labelPrice, recordPrice),
                  const SizedBox(height: 16),
                ],

                // Degisim gecmisi
                if (changed.isEmpty)
                  _buildNotChangedWarning(history.isEmpty)
                else
                  _buildChangedInfo(changed),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Etiket fiyati ile kayittaki guncel fiyati kiyaslar.
  /// Etiket < kayit ise fiyat farki hesaplanir (zararina olabilir).
  Widget _buildPriceComparison(double labelPrice, double? recordPrice) {
    // Kayitta fiyat yoksa kiyas yapilamaz.
    if (recordPrice == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: AppTheme.textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Etiket fiyatı: ${labelPrice.toStringAsFixed(2)} ₺\n'
                'Kayıtlarda bu ürünün fiyatı bulunamadı, kıyas yapılamıyor.',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    final diff = recordPrice - labelPrice; // pozitifse etiket daha dusuk
    final labelIsLower = diff > 0.001;
    final equal = diff.abs() <= 0.001;

    final Color color = labelIsLower
        ? AppTheme.statusExpired
        : AppTheme.statusSafe;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                labelIsLower
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
                color: color,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  labelIsLower
                      ? 'Etiket fiyatı DÜŞÜK!'
                      : (equal ? 'Fiyatlar uyuşuyor' : 'Sorun yok'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Fiyat satirlari
          _priceRow('Etikette yazan', labelPrice,
              bold: labelIsLower),
          const SizedBox(height: 6),
          _priceRow('Kayıttaki güncel', recordPrice),
          if (labelIsLower) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fiyat farkı',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                Text(
                  '${diff.toStringAsFixed(2)} ₺',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Etiketteki fiyat kayıttaki güncel fiyattan ${diff.toStringAsFixed(2)} ₺ düşük. '
              'Müşteri etiket fiyatını talep edebilir — bu fark senin aleyhine olabilir.',
              style: const TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
            ),
          ] else if (!equal) ...[
            const SizedBox(height: 8),
            const Text(
              'Etiket fiyatı kayıttaki fiyata eşit veya daha yüksek. Bir sorun yok.',
              style: TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _priceRow(String label, double price, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary)),
        Text(
          '${price.toStringAsFixed(2)} ₺',
          style: TextStyle(
              fontSize: 15,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildNotChangedWarning(bool neverSeen) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.statusExpired.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.statusExpired.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppTheme.statusExpired, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  neverSeen
                      ? 'Bu ürün hiç fiyat değişimine girmemiş'
                      : 'Fiyatı HENÜZ değiştirilmemiş',
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.statusExpired),
                ),
                const SizedBox(height: 6),
                Text(
                  neverSeen
                      ? 'Bu barkod hiçbir fiyat değişim oturumunda yer almamış. Yeni fiyat etiketi henüz uygulanmamış olabilir.'
                      : 'Bu ürün bir oturuma eklenmiş ama fiyatı değiştirildi olarak işaretlenmemiş. Eski fiyattan satılıyor olabilir — dikkat.',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangedInfo(List<PriceChangeItem> changed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.statusSafe.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.statusSafe.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppTheme.statusSafe, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  changed.length == 1
                      ? 'Fiyatı değiştirilmiş'
                      : '${changed.length} kez fiyat değişimi yapılmış',
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.statusSafe),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Değişim tarihleri:',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        ...changed.map((item) {
          final date = item.changedAt ?? item.createdAt;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_available_rounded,
                    size: 20, color: AppTheme.statusSafe),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('d MMMM yyyy', 'tr').format(date),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        DateFormat('EEEE • HH:mm', 'tr').format(date),
                        style: const TextStyle(
                            fontSize: 12.5, color: AppTheme.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _openSession(SessionSummary s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) =>
              PriceChangeSessionScreen(sessionId: s.session.id!)),
    );
    _load();
  }

  Future<void> _deleteSession(SessionSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oturumu Sil'),
        content: Text(
            '${DateFormat('dd.MM.yyyy').format(s.session.createdAt)} oturumu '
            've ${s.total} kalemi silinecek. (Kanıt fotoğrafları silinmez.) '
            'Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusExpired),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PriceChangeService.instance.deleteSession(s.session.id!);
      _load();
    }
  }

  /// Gemini API anahtari ayar dialogu.
  Future<void> _openKeySettings() async {
    final current = await GeminiOcrService.instance.getApiKey();
    if (!mounted) return;
    final ctrl = TextEditingController(text: current ?? '');
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Online OCR (Gemini)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A4 tablolarını yüksek doğrulukla okumak için Gemini API '
              'anahtarı gerekir. Ücretsiz: aistudio.google.com → '
              '"Get API key". Anahtar cihazda şifreli saklanır.',
              style: TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Anahtarı',
                hintText: 'AIza...',
              ),
            ),
          ],
        ),
        actions: [
          if (current != null && current.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: const Text('Anahtarı Sil',
                  style: TextStyle(color: AppTheme.statusExpired)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Kaydet')),
        ],
      ),
    );

    if (action == 'save' && ctrl.text.trim().isNotEmpty) {
      await GeminiOcrService.instance.setApiKey(ctrl.text);
    } else if (action == 'clear') {
      await GeminiOcrService.instance.clearApiKey();
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Fiyat Değişim'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_search_rounded, color: Colors.white),
            tooltip: 'Fiyat Geçmişi Sorgula',
            onPressed: _queryBarcode,
          ),
          IconButton(
            icon: Icon(
              _hasKey ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: _hasKey ? Colors.white : Colors.white70,
            ),
            tooltip: 'Online OCR Ayarı',
            onPressed: _openKeySettings,
          ),
        ],
      ),
      body: _loading
          ? const LoadingState()
          : _sessions.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _sessions.length + (_hasKey ? 0 : 1),
                    itemBuilder: (_, i) {
                      // Key yoksa en ustte uyari karti.
                      if (!_hasKey && i == 0) return _buildKeyBanner();
                      final s = _sessions[_hasKey ? i : i - 1];
                      return _sessionCard(s);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSession,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni Oturum'),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        if (!_hasKey)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildKeyBanner(),
          ),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: const EmptyState(
            icon: Icons.receipt_long_rounded,
            iconColor: AppTheme.coral,
            title: 'Henüz oturum yok',
            subtitle:
                'Her fiyat değişim günü bir oturumdur: A4 listeleri tara, '
                'etiketleri değiştir (fotolu kanıt), eksikleri raporla.\n'
                'Başlamak için "Yeni Oturum"a dokunun.',
          ),
        ),
      ],
    );
  }

  Widget _buildKeyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(accentColor: AppTheme.statusWarning),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppTheme.statusWarning, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Online OCR kapalı — A4 okuma doğruluğu düşük olabilir. '
              'Gemini anahtarı ekleyin (ücretsiz).',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: _openKeySettings,
            child: const Text('Ayarla'),
          ),
        ],
      ),
    );
  }

  Widget _sessionCard(SessionSummary s) {
    final fmtDate = DateFormat('dd MMMM yyyy', 'tr');
    final fmtTime = DateFormat('HH:mm');
    final done = s.session.isCompleted;
    final color = done
        ? AppTheme.statusSafe
        : (s.pending == 0 && s.total > 0
            ? AppTheme.statusSafe
            : AppTheme.primary);

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: () => _openSession(s),
      onLongPress: () => _deleteSession(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.card(accentColor: color),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      done
                          ? Icons.task_alt_rounded
                          : Icons.pending_actions_rounded,
                      color: color,
                      size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtDate.format(s.session.createdAt),
                          style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700)),
                      Text(
                        '${fmtTime.format(s.session.createdAt)}'
                        '${s.session.a4Count > 0 ? "  •  ${s.session.a4Count} A4" : ""}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textTertiary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius:
                        BorderRadius.circular(AppTheme.rPill),
                    border:
                        Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Text(
                    done ? 'Tamamlandı' : 'Devam ediyor',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
              ],
            ),
            if (s.total > 0) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: s.progress,
                  minHeight: 6,
                  backgroundColor: AppTheme.surfaceAlt,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _miniStat('Toplam', s.total, AppTheme.textSecondary),
                  const SizedBox(width: 14),
                  _miniStat('Değişti', s.changed, AppTheme.statusSafe),
                  const SizedBox(width: 14),
                  _miniStat(
                      'Kalan',
                      s.pending,
                      s.pending > 0
                          ? AppTheme.statusWarning
                          : AppTheme.statusSafe),
                ],
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Henüz A4 eklenmedi',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textTertiary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, int value, Color color) {
    return Row(
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11.5, color: AppTheme.textTertiary)),
      ],
    );
  }
}

/// Basit barkod tarayici — okudugu barkodu geri dondurur (sorgu icin).
class _BarcodeQueryScanner extends StatefulWidget {
  const _BarcodeQueryScanner();

  @override
  State<_BarcodeQueryScanner> createState() => _BarcodeQueryScannerState();
}

class _BarcodeQueryScannerState extends State<_BarcodeQueryScanner> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    // Yapisal QR ise barkod+fiyat birlikte coz.
    Navigator.of(context).pop(ScanParser.parse(value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        systemOverlayStyle: AppTheme.systemBarForColor(Colors.black),
        title: const Text('Barkod Okut'),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Tarama cercevesi
          Container(
            width: MediaQuery.of(context).size.width * 0.8,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 32,
            right: 32,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                'Sorgulamak için barkodu çerçeveye getir',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

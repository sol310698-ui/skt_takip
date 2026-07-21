import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/shelf_layout_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'shelf_layout_view_screen.dart';
import 'shelf_bulk_move_screen.dart';

/// ════════════════════════════════════════════════════════════════════
///  REYON DIZILIM — KUS BAKISI LISTE
/// ────────────────────────────────────────────────────────────────────
///  Olusturulan reyonlar kart izgarasi olarak gorunur. Bir reyona basinca
///  dizilim (planogram) ekrani acilir. "+ Reyon" ile yeni reyon olusturulur
///  (ad, bolum sayisi, satir sayisi). Bir depoya bagli acilirsa (warehouseId)
///  yalnizca o deponun reyonlari listelenir.
/// ════════════════════════════════════════════════════════════════════
class ShelfLayoutListScreen extends StatefulWidget {
  final int? warehouseId;
  final String? warehouseName;
  /// Nav sekmesi koku olarak mi acildi (hero baslikta geri tusu yok).
  final bool isTabRoot;
  const ShelfLayoutListScreen(
      {super.key, this.warehouseId, this.warehouseName, this.isTabRoot = false});

  @override
  State<ShelfLayoutListScreen> createState() => _ShelfLayoutListScreenState();
}

class _ShelfLayoutListScreenState extends State<ShelfLayoutListScreen> {
  List<ShelfUnitSummary> _units = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final units = await ShelfLayoutService.instance
        .getUnitSummaries(warehouseId: widget.warehouseId);
    if (mounted) setState(() {
      _units = units;
      _loading = false;
    });
  }

  Future<void> _openBulkMove() async {
    final moved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ShelfBulkMoveScreen(),
      ),
    );
    if (moved == true) _load();
  }

  Future<void> _newUnit() async {
    final nameCtrl = TextEditingController(
        text: 'Reyon ${_units.length + 1}');
    int sections = 4;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Yeni Reyon'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Reyon adı',
                  hintText: 'Reyon 1, Bakliyat...',
                ),
              ),
              const SizedBox(height: 18),
              _stepper(
                label: 'Sütun sayısı',
                help: 'Reyonun soldan sağa kaç sütunu var. Raflar ve '
                    'ürünler sonra serbestçe eklenir (sınır yok).',
                value: sections,
                onChanged: (v) => setD(() => sections = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Oluştur')),
          ],
        ),
      ),
    );

    if (created != true) return;
    final id = await ShelfLayoutService.instance.createUnit(
      name: nameCtrl.text.trim().isEmpty ? 'Reyon' : nameCtrl.text.trim(),
      sections: sections,
      warehouseId: widget.warehouseId,
    );
    await _load();
    if (!mounted) return;
    // Yeni reyon olusturunca dogrudan dizilim (planogram) ekranini ac;
    // kullanici oradan sutun sutun raf/urun ekler.
    final unit = await ShelfLayoutService.instance.getUnit(id);
    if (unit != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ShelfLayoutViewScreen(unitId: unit.id!)));
      _load();
    }
  }

  Widget _stepper({
    required String label,
    required String help,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(help,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 34,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900)),
        ),
        IconButton.filledTonal(
          onPressed: value < 20 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(ShelfUnitSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reyonu Sil'),
        content: Text(
            '"${s.unit.name}" ve içindeki ${s.itemCount} ürün fotoğrafı '
            'silinecek. Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.statusExpired),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      await ShelfLayoutService.instance.deleteUnit(s.unit.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom + 16;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _hero(),
          Expanded(
            child: _loading
                ? const LoadingState()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad),
                      children: [
                        if (_units.isEmpty) _emptyCard(),
                        ..._units.map(_card),
                        _addCard(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// ── HERO ─ Reyon sekmesinin kimliği: primary gradyan + özet.
  Widget _hero() {
    final topPad = MediaQuery.of(context).padding.top;
    final canPop = !widget.isTabRoot && Navigator.of(context).canPop();
    final totalItems = _units.fold(0, (s, u) => s + u.itemCount);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(canPop ? 8 : 20, topPad + 14, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary,
            Color.lerp(AppTheme.primary, AppTheme.accent, 0.45)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white),
            ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.shelves, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.warehouseName != null
                      ? 'Reyonlar — ${widget.warehouseName}'
                      : 'Reyon',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
                Text(
                  _loading
                      ? 'Dizilimler yükleniyor…'
                      : '${_units.length} reyon · $totalItems ürün',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          if (_units.length >= 2)
            IconButton(
              onPressed: _openBulkMove,
              tooltip: 'Toplu Sütun Taşı',
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.swap_horiz_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          IconButton(
            onPressed: _newUnit,
            tooltip: 'Yeni Reyon',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_rounded,
                  color: AppTheme.primary, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  /// ── KART ─ tam genişlik, kapak fotoğraflı; fotoğraf yoksa reyonun
  /// sütun sayısına göre çizilmiş MİNİ PLANOGRAM arka planı.
  Widget _card(ShelfUnitSummary s) {
    final hasPhoto =
        s.coverPhoto != null && File(s.coverPhoto!).existsSync();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ShelfLayoutViewScreen(unitId: s.unit.id!)));
          _load();
        },
        onLongPress: () => _confirmDelete(s),
        child: Container(
          height: 150,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
            boxShadow: AppTheme.shadowMd,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Arka plan: kapak fotoğrafı ya da mini planogram.
              hasPhoto
                  ? Image.file(File(s.coverPhoto!), fit: BoxFit.cover)
                  : CustomPaint(
                      painter: _MiniPlanogramPainter(
                        sections: s.unit.sections,
                        accent: AppTheme.primary,
                        isLight: AppTheme.isLight,
                      ),
                    ),
              // Okunabilirlik: alttan koyu gradyan perde.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(hasPhoto ? 0.10 : 0.0),
                      Colors.black.withOpacity(0.62),
                    ],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),
              // İçerik: ad + bilgi çipleri + dizilim oku.
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      s.unit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _chip(Icons.view_week_rounded,
                            '${s.unit.sections} sütun'),
                        const SizedBox(width: 8),
                        _chip(Icons.inventory_2_rounded,
                            '${s.itemCount} ürün'),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius:
                                BorderRadius.circular(AppTheme.rPill),
                          ),
                          child: const Row(
                            children: [
                              Text('Dizilim',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              SizedBox(width: 3),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 14, color: Colors.white),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(AppTheme.rPill),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ],
        ),
      );

  /// Kesikli çerçeveli "Yeni Reyon" ekleme kartı — listenin sonunda.
  Widget _addCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: _newUnit,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          color: AppTheme.primary.withOpacity(0.06),
          border: Border.all(
              color: AppTheme.primary.withOpacity(0.45), width: 1.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('Yeni Reyon',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary)),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.card(),
      child: Column(
        children: [
          Icon(Icons.shelves,
              size: 48, color: AppTheme.primary.withOpacity(0.5)),
          const SizedBox(height: 12),
          const Text('Henüz reyon yok',
              style:
                  TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Bir reyon oluşturun (sütun sayısı), sonra ürünleri okutup '
            'fotoğraflayın. Dizilimi kuş bakışı görebilirsiniz.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Fotoğrafı olmayan reyon kartının arka planı: sütun sayısına göre
/// basit bir raf dizilimi (planogram) çizer — her sütunda 3 raf bandı,
/// bantların üstünde rastgele-ymiş gibi (deterministik) ürün blokları.
class _MiniPlanogramPainter extends CustomPainter {
  final int sections;
  final Color accent;
  final bool isLight;
  _MiniPlanogramPainter({
    required this.sections,
    required this.accent,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = isLight ? const Color(0xFFEDEFF4) : const Color(0xFF171A21);
    canvas.drawRect(Offset.zero & size, bg);

    final n = sections.clamp(1, 12);
    const pad = 10.0, gap = 6.0;
    final colW = (size.width - pad * 2 - gap * (n - 1)) / n;
    final shelf = Paint()..color = accent.withOpacity(0.30);
    final box = Paint()..color = accent.withOpacity(0.55);

    for (int c = 0; c < n; c++) {
      final x = pad + c * (colW + gap);
      for (int r = 0; r < 3; r++) {
        final y = pad + 12 + r * ((size.height - pad * 2) / 3);
        // Raf bandı.
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y + 24, colW, 4),
                const Radius.circular(2)),
            shelf);
        // Ürün blokları (deterministik desen: sütun+raf'a göre 2-3 kutu).
        final k = 2 + ((c + r) % 2);
        final bw = (colW - (k - 1) * 3) / k;
        for (int b = 0; b < k; b++) {
          final bh = 12.0 + ((c * 3 + r * 5 + b * 7) % 3) * 4;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(
                      x + b * (bw + 3), y + 24 - bh, bw, bh),
                  const Radius.circular(2)),
              box);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MiniPlanogramPainter old) =>
      old.sections != sections ||
      old.accent != accent ||
      old.isLight != isLight;
}

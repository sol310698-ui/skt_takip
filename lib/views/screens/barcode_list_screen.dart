import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/nav_bar_visibility.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';
import '../widgets/scroll_to_top_fab.dart';
import '../widgets/ui_kit.dart';
import 'barcode_detail_screen.dart';
import 'barcode_entry_screen.dart';
import 'import_screen.dart';

/// Barkod dizini liste ekrani (Excel'den import edilenler).
class BarcodeListScreen extends ConsumerStatefulWidget {
  final bool isActive;
  const BarcodeListScreen({super.key, this.isActive = true});

  @override
  ConsumerState<BarcodeListScreen> createState() =>
      _BarcodeListScreenState();
}

class _BarcodeListScreenState extends ConsumerState<BarcodeListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  String _query = '';
  List<BarcodeEntry> _all = [];
  bool _loading = true;
  bool _searchVisible = true; // asagi kaydirinca gizlenir

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  void _onScroll() {
    final dir = _scrollCtrl.position.userScrollDirection;
    if (dir == ScrollDirection.reverse && _searchVisible) {
      setState(() => _searchVisible = false);
    } else if (dir == ScrollDirection.forward && !_searchVisible) {
      setState(() => _searchVisible = true);
    }
    handleNavBarScroll(_scrollCtrl);
  }

  @override
  void didUpdateWidget(BarcodeListScreen old) {
    super.didUpdateWidget(old);
    // Sekmeye geri donulunce listeyi yenile.
    if (widget.isActive && !old.isActive) {
      _load();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _speech.stop();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list =
        await ref.read(barcodeDirectoryRepositoryProvider).getAll();
    if (mounted) {
      setState(() {
        _all = list;
        _loading = false;
      });
    }
  }

  List<BarcodeEntry> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all
        .where((e) =>
            e.barcode.toLowerCase().contains(q) ||
            e.productName.toLowerCase().contains(q) ||
            (e.stockCode?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  // ════════════════════════════════════════════════════════════════════
  //  KESIK BARKOD MODU
  // ────────────────────────────────────────────────────────────────────
  //  Etiket yirtik/silik oldugunda barkodun yalnizca bir PARCASI okunur
  //  (bastan, ortadan ya da sondan). Bu mod, girilen rakam parcasina gore:
  //   1) ICERENLER — parcanin barkodun herhangi bir yerinde AYNEN gectigi
  //      kayitlar (eslesen kisim vurgulanir; basta/ortada/sonda etiketi).
  //   2) BENZERLER — parca birebir gecmese de, EN FAZLA 1 (parca >=8 hane
  //      ise 2) hanesi FARKLI olacak sekilde hizalanabilen kayitlar. Silik
  //      basilmis/yanlis okunmus tek haneyi tolere eder.
  //  Mod, arama kutusundaki MAKAS dugmesiyle acilir; yalnizca rakam
  //  girisiyle calisir (>=4 hane).
  // ════════════════════════════════════════════════════════════════════
  bool _fragmentMode = false;

  // ── SESLI ARAMA ──
  // Eldivenle/islak elle yazmak zordur; mikrofona urun adini soyle,
  // arama kutusuna yazilip liste aninda filtrelenir.
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;

  Future<void> _voiceSearch() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return;
    final ok = await _speech.initialize(
      onStatus: (st) {
        if ((st == 'done' || st == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ok || !mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      localeId: 'tr_TR',
      pauseFor: const Duration(seconds: 2),
      listenOptions: stt.SpeechListenOptions(partialResults: true),
      onResult: (r) {
        if (!mounted) return;
        setState(() {
          _searchCtrl.text = r.recognizedWords;
          _query = r.recognizedWords;
          if (r.finalResult) _listening = false;
        });
      },
    );
  }

  ({List<(BarcodeEntry, int)> exact, List<(BarcodeEntry, int, int)> similar})
      _fragmentResults() {
    final q = _query.replaceAll(RegExp(r'\D'), '');
    final exact = <(BarcodeEntry, int)>[]; // (kayit, eslesme baslangici)
    final similar = <(BarcodeEntry, int, int)>[]; // (kayit, poz, fark)
    if (q.length < 4) return (exact: exact, similar: similar);

    final maxDiff = q.length >= 8 ? 2 : 1;

    for (final e in _all) {
      final b = e.barcode;
      final idx = b.indexOf(q);
      if (idx >= 0) {
        exact.add((e, idx));
        continue;
      }
      // Benzerlik: parcayi barkodun her pozisyonuna hizala, hane farki say.
      int bestDiff = 999, bestPos = -1;
      for (int p = 0; p + q.length <= b.length; p++) {
        int diff = 0;
        for (int k = 0; k < q.length; k++) {
          if (b[p + k] != q[k]) {
            diff++;
            if (diff > maxDiff) break;
          }
        }
        if (diff <= maxDiff && diff < bestDiff) {
          bestDiff = diff;
          bestPos = p;
          if (diff == 1) break; // daha iyisi ancak 1 olur (0 = exact idi)
        }
      }
      if (bestPos >= 0) similar.add((e, bestPos, bestDiff));
    }
    // Benzerleri az farktan coga sirala.
    similar.sort((a, b) => a.$3.compareTo(b.$3));
    return (exact: exact, similar: similar);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBarForColor(AppTheme.primary),
      child: Scaffold(
        body: Stack(
          children: [
            Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _loading
                        ? const LoadingState()
                        : _all.isEmpty
                            ? _buildEmpty()
                            : _fragmentMode
                                ? _buildFragmentList()
                                : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView.separated(
                                  controller: _scrollCtrl,
                                  padding: const EdgeInsets.only(
                                      top: 8, bottom: 100),
                                  itemCount: _filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1, indent: 60),
                                  itemBuilder: (context, i) =>
                                      _tile(_filtered[i]),
                                ),
                              ),
                  ),
                ],
              ),
            // Sol altta: yukari cik FAB (sag altta "Manuel Ekle" FAB'i
            // oldugu icin cakismayi onlemek icin sol kose kullanilir).
            ScrollToTopFab(
              controller: _scrollCtrl,
              baseBottomPadding: 108,
            ),
            // Sag altta: "Manuel Ekle". Nav bar ile SENKRON: nav bar
            // gizlenince asagi iner, acilinca cikar (floating nav bar ile
            // cakismaz).
            Positioned(
              right: 16,
              bottom: 108,
              child: ValueListenableBuilder<bool>(
                valueListenable: navBarVisible,
                builder: (_, navVisible, child) => AnimatedSlide(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  offset: navVisible ? Offset.zero : const Offset(0, 1.6),
                  child: child,
                ),
                child: FloatingActionButton.extended(
                  heroTag: 'bc_add_single',
                  onPressed: _openAddEntry,
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Manuel Ekle',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final topInset = MediaQuery.of(context).padding.top;
    return AuroraBackground(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: Container(
      padding: EdgeInsets.fromLTRB(20, 16 + topInset, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Baslik + kayit sayisi yan yana (alan kazanmak icin).
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text('Barkod Listesi',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    Text('${_all.length} kayıt',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.upload_file_outlined,
                    color: Colors.white),
                tooltip: 'Excel Import',
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ImportScreen()));
                  _load();
                },
              ),
            ],
          ),
          // Arama: asagi kaydirinca gizlenir.
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _searchVisible
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      keyboardType: _fragmentMode
                          ? TextInputType.number
                          : TextInputType.text,
                      // Disari dokununca/arama yapinca klavye kapanir ve
                      // imlec birakilir (geri donunce klavye acilmaz).
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onSubmitted: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: _fragmentMode
                            ? 'Barkodun okunan kısmını gir (en az 4 hane)'
                            : 'Barkod, ürün veya stok kodu ara...',
                        prefixIcon: const Icon(Icons.search),
                        // SESLI ARAMA + KESIK BARKOD dugmeleri yan yana.
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Sesli ara',
                              icon: Icon(
                                _listening
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                color: _listening
                                    ? AppTheme.statusExpired
                                    : AppTheme.textTertiary,
                              ),
                              onPressed: _voiceSearch,
                            ),
                            IconButton(
                              tooltip: 'Kesik barkod ara',
                              icon: Icon(
                                Icons.content_cut_rounded,
                                color: _fragmentMode
                                    ? AppTheme.primary
                                    : AppTheme.textTertiary,
                              ),
                              onPressed: () => setState(
                                  () => _fragmentMode = !_fragmentMode),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
      ),
    );
  }

  /// KESIK BARKOD sonuc listesi: once parcayi AYNEN icerenler, sonra
  /// 1-2 hane farkla BENZEYENLER. Eslesen kisim renkli vurgulanir.
  Widget _buildFragmentList() {
    final digits = _query.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.content_cut_rounded,
                  size: 48, color: AppTheme.textTertiary),
              const SizedBox(height: 12),
              Text(
                'Yırtık/silik etiketteki barkodun okunabilen kısmını gir '
                '(en az 4 rakam). Baştan, ortadan ya da sondan olması fark '
                'etmez — içeren ve benzeyen kayıtları bulurum.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final r = _fragmentResults();
    if (r.exact.isEmpty && r.similar.isEmpty) {
      return Center(
        child: Text('“$digits” ile eşleşen ya da benzeyen barkod yok',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    final children = <Widget>[];
    if (r.exact.isNotEmpty) {
      children.add(_fragmentHeader(
          'Parçayı içerenler (${r.exact.length})', AppTheme.statusSafe));
      for (final (e, pos) in r.exact) {
        children.add(_fragmentTile(e, pos, digits.length, 0));
      }
    }
    if (r.similar.isNotEmpty) {
      children.add(_fragmentHeader(
          'Benzerler — 1-2 hane farklı (${r.similar.length})',
          AppTheme.statusWarning));
      for (final (e, pos, diff) in r.similar) {
        children.add(_fragmentTile(e, pos, digits.length, diff));
      }
    }
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      children: children,
    );
  }

  Widget _fragmentHeader(String text, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(text,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textSecondary)),
          ],
        ),
      );

  /// Eslesen araligi renkli gosteren kayit satiri. [diff]=0 icerme,
  /// >0 benzerlik (fark sayisi rozeti gosterilir). Konum etiketi: parca
  /// barkodun basinda/ortasinda/sonunda mi.
  Widget _fragmentTile(BarcodeEntry e, int pos, int len, int diff) {
    final b = e.barcode;
    final end = (pos + len).clamp(0, b.length);
    final where = pos == 0
        ? 'başta'
        : (end >= b.length ? 'sonda' : 'ortada');
    final hl = diff == 0 ? AppTheme.statusSafe : AppTheme.statusWarning;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.qr_code, color: AppTheme.primary, size: 22),
      ),
      title: Text(e.productName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: RichText(
        text: TextSpan(
          style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: AppTheme.textSecondary),
          children: [
            TextSpan(text: b.substring(0, pos)),
            TextSpan(
              text: b.substring(pos, end),
              style: TextStyle(
                color: hl,
                fontWeight: FontWeight.w900,
                backgroundColor: hl.withOpacity(0.15),
              ),
            ),
            TextSpan(text: b.substring(end)),
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(where,
              style: TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
          if (diff > 0)
            Text('$diff hane farklı',
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.statusWarning,
                    fontWeight: FontWeight.w700)),
        ],
      ),
      onTap: () async {
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => BarcodeDetailScreen(entry: e)),
        );
        if (changed == true) _load();
      },
    );
  }

  Widget _tile(BarcodeEntry e) {
    return Dismissible(
      key: ValueKey('bc_${e.id}_${e.barcode}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppTheme.statusExpired,
          borderRadius: BorderRadius.circular(0),
        ),
        child: const Icon(Icons.delete_rounded,
            color: Colors.white, size: 26),
      ),
      confirmDismiss: (_) => _confirmDelete(e),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              Icon(Icons.qr_code, color: AppTheme.primary, size: 22),
        ),
        title: Text(e.productName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            e.stockCode != null && e.stockCode!.isNotEmpty
                ? '${e.barcode}  •  Stok: ${e.stockCode}'
                : e.barcode,
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: AppTheme.textSecondary)),
        trailing: Icon(Icons.chevron_right_rounded,
            color: AppTheme.textTertiary),
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => BarcodeDetailScreen(entry: e),
            ),
          );
          if (changed == true) _load();
        },
      ),
    );
  }

  /// Silme onayi. Benzer barkod/ayni ad varsa ozel uyari gosterir.
  Future<bool> _confirmDelete(BarcodeEntry e) async {
    final similar = await ref
        .read(barcodeDirectoryRepositoryProvider)
        .countSimilar(
          excludeId: e.id ?? -1,
          productName: e.productName,
          barcode: e.barcode,
        );

    if (!mounted) return false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barkodu Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${e.productName}"\n${e.barcode}'),
            if (similar > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.statusWarning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.statusWarning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu ürünle aynı ad veya benzer barkoda sahip $similar kayıt daha var.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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

    if (ok == true && e.id != null) {
      await ref
          .read(barcodeDirectoryRepositoryProvider)
          .deleteById(e.id!);
      await _load();
      return true;
    }
    return false;
  }

  Widget _buildEmpty() {
    return EmptyState(
      icon: Icons.qr_code_2_rounded,
      title: 'Barkod listesi boş',
      subtitle: 'Excel ile barkod listesi yükleyin veya tarayarak ekleyin',
      action: FilledButton.icon(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ImportScreen()));
          _load();
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Excel Yükle'),
      ),
    );
  }

  /// Manuel barkod + ad girisi (BarcodeEntryScreen).
  Future<void> _openAddEntry() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BarcodeEntryScreen()),
    );
    if (added == true) _load();
  }
}

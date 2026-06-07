import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';
import '../widgets/google_search_button.dart';
import 'import_screen.dart';
import 'universal_scan_screen.dart';

/// Barkod dizini liste ekrani (Excel'den import edilenler).
class BarcodeListScreen extends ConsumerStatefulWidget {
  const BarcodeListScreen({super.key});

  @override
  ConsumerState<BarcodeListScreen> createState() =>
      _BarcodeListScreenState();
}

class _BarcodeListScreenState extends ConsumerState<BarcodeListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  List<BarcodeEntry> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
            e.productName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _all.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.only(
                                top: 8, bottom: 100),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, indent: 60),
                            itemBuilder: (context, i) =>
                                _tile(_filtered[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScan,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Tara'),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: AppTheme.bannerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Barkod Listesi',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
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
          const SizedBox(height: 6),
          Text('${_all.length} kayıtlı barkod',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85), fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Barkod veya ürün ara...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BarcodeEntry e) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.qr_code, color: AppTheme.primary, size: 22),
      ),
      title: Text(e.productName,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(e.barcode,
          style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: AppTheme.textSecondary)),
      trailing: GoogleSearchButton(query: e.barcode, compact: true),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_2,
              size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          const Text('Barkod listesi boş',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Excel ile barkod listesi yükleyin',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ImportScreen()));
              _load();
            },
            icon: const Icon(Icons.upload_file),
            label: const Text('Excel Yükle'),
          ),
        ],
      ),
    );
  }

  Future<void> _openScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UniversalScanScreen()),
    );
    _load();
  }
}

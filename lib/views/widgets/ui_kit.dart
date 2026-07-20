import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/database_service.dart';
import '../../data/datasources/barcode_directory_datasource.dart';

/// ════════════════════════════════════════════════════════════════════
///  Paylasilan UI bilesenleri — tum ekranlarda tutarli gorunum.
/// ════════════════════════════════════════════════════════════════════

/// Sik bos durum gostergesi (ikon + baslik + alt metin + opsiyonel aksiyon).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? iconColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = iconColor ?? AppTheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.withOpacity(0.22), c.withOpacity(0.06)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: c.withOpacity(0.25), width: 1.5),
              ),
              child: Icon(icon, size: 44, color: c),
            ),
            const SizedBox(height: AppTheme.s20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppTheme.s8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppTheme.s24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Tutarli yukleniyor gostergesi (opsiyonel metin).
class LoadingState extends StatelessWidget {
  final String? message;
  const LoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: AppTheme.primary),
          ),
          if (message != null) ...[
            const SizedBox(height: AppTheme.s16),
            Text(message!,
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// Hata durumu gostergesi.
class ErrorStateView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorStateView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppTheme.statusExpired),
            const SizedBox(height: AppTheme.s16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary)),
            if (onRetry != null) ...[
              const SizedBox(height: AppTheme.s20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Form/sayfa bolum basligi (kucuk, ikincil renk, harf araligi).
class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsets padding;
  const SectionLabel(this.text,
      {super.key,
      this.padding = const EdgeInsets.only(left: 4, bottom: AppTheme.s8)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppTheme.textTertiary,
        ),
      ),
    );
  }
}

/// Kucuk renkli istatistik/metrik karti.
class StatTile extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const StatTile({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text('$count',
              style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Urun gorseli — ONCELIK: TELEFONDAKI (yerel) foto 1., internet 2. planda.
/// "Telefondaki foto her zaman internetten daha degerlidir" kurali: yerel
/// foto varsa internet gorseline HIC bakilmaz; yerel yoksa internete duser;
/// o da yoksa yer tutucu ikon gosterilir.
///
/// - [directLocalPath] verilmisse (orn. reyon slotunun kendi fotografi) dogrudan
///   o dosya kullanilir (en oncelikli).
/// - [barcode] verilmisse barkod dizinindeki local_image_path once cozulur;
///   varsa gosterilir (internet beklemeden).
/// - [networkUrl] yalnizca yerel foto YOKKEN devreye girer (2. plan).
class SmartProductImage extends StatefulWidget {
  final String? networkUrl;
  final String? barcode;
  final String? directLocalPath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function()? placeholder;

  const SmartProductImage({
    super.key,
    this.networkUrl,
    this.barcode,
    this.directLocalPath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  State<SmartProductImage> createState() => _SmartProductImageState();
}

class _SmartProductImageState extends State<SmartProductImage> {
  String? _localPath;
  bool _resolving = false;
  bool _networkFailed = false;
  // Yerel foto arama TAMAMLANDI mi? Tamamlanana kadar internet gosterilmez
  // (yerel foto varsa internet hic gorunmesin, titreme olmasin).
  bool _localResolved = false;

  @override
  void initState() {
    super.initState();
    _localPath = widget.directLocalPath;
    // ONCELIK: TELEFONDAKI (yerel) fotograf her zaman internetten daha
    // degerlidir. Bu yuzden barkod verilmisse — internet URL'i olsa bile —
    // once yerel fotografi cozmeye calisiriz; varsa onu gosteririz, yoksa
    // internete duseriz.
    if (_localPath == null) {
      _resolveLocal();
    }
  }

  Future<void> _resolveLocal() async {
    if (_resolving) return;
    if (widget.barcode == null || widget.barcode!.isEmpty) {
      // Cozecek barkod yok; internete gecebilmek icin cozumlemeyi bitmis say.
      if (mounted) setState(() => _localResolved = true);
      return;
    }
    _resolving = true;
    try {
      final ds = BarcodeDirectoryDataSource(DatabaseService.instance);
      final path = await ds.getLocalImage(widget.barcode!);
      if (mounted) {
        setState(() {
          if (path != null && File(path).existsSync()) _localPath = path;
          _localResolved = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _localResolved = true);
    }
  }

  Widget _ph() =>
      widget.placeholder?.call() ??
      Container(
        color: AppTheme.surfaceAlt,
        child: Icon(Icons.inventory_2_rounded, color: AppTheme.textTertiary),
      );

  @override
  Widget build(BuildContext context) {
    // ONCELIK 1: Telefondaki (yerel) fotograf. Varsa her zaman o gosterilir,
    // internet fotografina hic bakilmaz.
    if (_localPath != null) return _localFile();

    // Yerel foto aramasi henuz bitmediyse: internete gecmeden once bekle
    // (yerel foto varsa aninda gosterilsin, arada internet flash'i olmasin).
    if (!_localResolved &&
        widget.barcode != null &&
        widget.barcode!.isNotEmpty) {
      return _ph();
    }

    // ONCELIK 2: Yerel foto yoksa internet fotografi (varsa) denenir.
    final hasNet = widget.networkUrl != null &&
        widget.networkUrl!.isNotEmpty &&
        !_networkFailed;

    if (hasNet) {
      return CachedNetworkImage(
        imageUrl: widget.networkUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (c, _) => _ph(),
        errorWidget: (c, _, __) {
          // Internet fotografi da yuklenemedi -> yer tutucu.
          if (!_networkFailed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _networkFailed = true);
            });
          }
          return _ph();
        },
      );
    }

    return _ph();
  }

  Widget _localFile() => Image.file(
        File(_localPath!),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => _ph(),
      );
}

class CachedImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function()? placeholder;

  const CachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      placeholder: (c, _) => placeholder != null
          ? placeholder!()
          : Container(
              color: AppTheme.surfaceAlt,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary),
                ),
              ),
            ),
      errorWidget: (c, _, __) => placeholder != null
          ? placeholder!()
          : Container(
              color: AppTheme.surfaceAlt,
              child: Icon(Icons.inventory_2_rounded,
                  color: AppTheme.textTertiary),
            ),
    );
  }
}

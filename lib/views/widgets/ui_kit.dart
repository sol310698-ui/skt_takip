import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/database_service.dart';
import '../../data/datasources/barcode_directory_datasource.dart';

/// ════════════════════════════════════════════════════════════════════
///  Paylasilan UI bilesenleri — tum ekranlarda tutarli gorunum.
/// ════════════════════════════════════════════════════════════════════

/// Sik bos durum gostergesi (ikon + baslik + alt metin + opsiyonel aksiyon).
/// #6: acilista nazikce belirir (fade + hafif olceklenme). `celebrate=true`
/// ile basari/tebrik varyanti (yesil onay, hafif ziplama).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? iconColor;

  /// Basari/tebrik varyanti (yesil onay tonu + ziplama).
  final bool celebrate;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconColor,
    this.celebrate = false,
  });

  @override
  Widget build(BuildContext context) {
    final c =
        iconColor ?? (celebrate ? AppTheme.statusSafe : AppTheme.primary);

    Widget art = Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.withOpacity(0.22), c.withOpacity(0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: c.withOpacity(0.25), width: 1.5),
        boxShadow: AppTheme.glow(c),
      ),
      child: Icon(icon, size: 46, color: c),
    );

    // Giris canlandirmasi: fade + olceklenme. Basari ise daha "ziplayan" egri.
    art = art.animate().fadeIn(duration: 400.ms).scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1, 1),
          duration: celebrate ? 550.ms : 420.ms,
          curve: celebrate ? Curves.elasticOut : Curves.easeOutBack,
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            art,
            const SizedBox(height: AppTheme.s20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ).animate().fadeIn(delay: 120.ms, duration: 380.ms),
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
              ).animate().fadeIn(delay: 190.ms, duration: 380.ms),
            ],
            if (action != null) ...[
              const SizedBox(height: AppTheme.s24),
              action!.animate().fadeIn(delay: 280.ms, duration: 380.ms),
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
          SizedBox(
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

/// ════════════════════════════════════════════════════════════════════
///  SKELETON SHIMMER — veri yuklenirken gercek kart sekillerinde parlayan
///  gri placeholder'lar (donen cember yerine). Paket gerektirmez; kendi
///  gradyan animasyonuyla soldan saga akan bir isik bandi cizer.
/// ════════════════════════════════════════════════════════════════════

/// Tek bir shimmer bloku — verilen boyut/yuvarlaklikta parlayan dikdortgen.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Liste iskeleti: [count] adet kart-benzeri satir (sol kare + iki metin
/// cizgisi). Cogu liste ekraninin yuklenme hali icin hazir sablon.
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsets padding;
  const SkeletonList({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Row(
          children: [
            const SkeletonBox(width: 46, height: 46, radius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 180, height: 13),
                  SizedBox(height: 8),
                  SkeletonBox(width: 110, height: 11),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const SkeletonBox(width: 40, height: 22, radius: 8),
          ],
        ),
      ),
    );
  }
}

/// Kart izgarasi iskeleti (reyon listesi gibi galeri/grid ekranlar icin).
class SkeletonGrid extends StatelessWidget {
  final int count;
  final int crossAxisCount;
  final double childAspectRatio;
  const SkeletonGrid({
    super.key,
    this.count = 6,
    this.crossAxisCount = 2,
    this.childAspectRatio = 1.6,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: count,
      itemBuilder: (_, __) => _Shimmer(
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(AppTheme.rLg),
          ),
        ),
      ),
    );
  }
}

/// Soldan saga akan isik bandiyla cocugunu parlatan sarici.
class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.isLight
        ? Colors.white.withOpacity(0.55)
        : Colors.white.withOpacity(0.06);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final dx = (rect.width + 200) * _c.value - 100;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                base,
                Colors.transparent,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideGradient(dx / rect.width),
            ).createShader(rect);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Gradyani yatayda kaydiran yardimci transform.
class _SlideGradient extends GradientTransform {
  final double t; // -1..1 civari, gradyanin merkez konumu
  const _SlideGradient(this.t);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * t, 0, 0);
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
              child: Center(
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

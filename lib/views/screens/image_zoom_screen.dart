import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Bir gorsel kaynagi: ag URL'si veya yerel dosya yolu.
class PhotoItem {
  final String? networkUrl;
  final String? filePath;
  final String? title;
  const PhotoItem({this.networkUrl, this.filePath, this.title});

  bool get isValid => networkUrl != null || filePath != null;

  ImageProvider get provider => networkUrl != null
      ? CachedNetworkImageProvider(networkUrl!)
      : FileImage(File(filePath!)) as ImageProvider;
}

/// ════════════════════════════════════════════════════════════════════
///  ÖZEL FOTOĞRAF GÖRÜNTÜLEYİCİ — sifirdan jest motoru, hicbir dis paket yok.
///
///  - Bulanik buyutulmus arka plan (derinlik / cam efekti)
///  - Pinch-zoom (parmak odagina gore), pan, momentum
///  - Cift dokunusla akilli zoom (dokunulan noktaya odakli)
///  - Asagi/yukari surukleyerek kapatma (kucult + soluklas + yaylan)
///  - Dokununca beliren/kaybolan ust bar + alt aksiyon cubugu
///  - Coklu gorsel galerisi: kaydirma + nokta gostergesi
/// ════════════════════════════════════════════════════════════════════
class PhotoViewerScreen extends StatefulWidget {
  final List<PhotoItem> items;
  final int initialIndex;
  final String? heroTag;

  const PhotoViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.heroTag,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pageController;
  late int _index;
  bool _controlsVisible = true;
  // Sayfa kaydirmayi sadece zoom yokken acmak icin.
  bool _zoomedOnCurrent = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _index);
    // Immersive modu acilis animasyonu bitince uygula (jank olmasin).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  Future<void> _share() async {
    final item = widget.items[_index];
    if (item.filePath != null && File(item.filePath!).existsSync()) {
      await Share.shareXFiles([XFile(item.filePath!)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final hasShare = item.filePath != null;
    final multiple = widget.items.length > 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Arka plan: hafif soluk + koyu (blur yok, performansli) ──
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Container(
                key: ValueKey(_index),
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: ResizeImage(
                      item.provider,
                      width: 120, // arka plan icin minik cozunurluk yeter
                    ),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.7),
                      BlendMode.darken,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Gorsel(ler) — kaydirilabilir galeri ──
          PageView.builder(
            controller: _pageController,
            // Zoom varken sayfa kaymasin.
            physics: _zoomedOnCurrent
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() {
              _index = i;
              _zoomedOnCurrent = false;
            }),
            itemBuilder: (context, i) {
              return _ZoomablePhoto(
                key: ValueKey('zoom_$i'),
                item: widget.items[i],
                heroTag: (widget.heroTag != null && i == widget.initialIndex)
                    ? widget.heroTag
                    : null,
                onTap: _toggleControls,
                onDismiss: _close,
                onZoomChanged: (zoomed) {
                  if (zoomed != _zoomedOnCurrent) {
                    setState(() => _zoomedOnCurrent = zoomed);
                  }
                },
              );
            },
          ),

          // ── Ust bar (baslik + kapat) ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            top: _controlsVisible ? 0 : -120,
            left: 0,
            right: 0,
            child: _TopBar(
              title: multiple
                  ? '${_index + 1} / ${widget.items.length}'
                  : (item.title ?? ''),
              onClose: _close,
            ),
          ),

          // ── Alt aksiyon cubugu + nokta gostergesi ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            bottom: _controlsVisible ? 0 : -160,
            left: 0,
            right: 0,
            child: _BottomBar(
              showShare: hasShare,
              onShare: _share,
              dotCount: multiple ? widget.items.length : 0,
              activeDot: _index,
            ),
          ),
        ],
      ),
    );
  }
}

/// ── Ust bar ──────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  const _TopBar({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 16,
        left: 8,
        right: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.6), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          _CircleButton(icon: Icons.close_rounded, onTap: onClose),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// ── Alt aksiyon cubugu ───────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final bool showShare;
  final VoidCallback onShare;
  final int dotCount;
  final int activeDot;

  const _BottomBar({
    required this.showShare,
    required this.onShare,
    required this.dotCount,
    required this.activeDot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 20,
        top: 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.6), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nokta gostergesi (coklu gorselse).
          if (dotCount > 1) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(dotCount, (i) {
                final active = i == activeDot;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
          ],
          if (showShare)
            _PillButton(
              icon: Icons.ios_share_rounded,
              label: 'Paylaş',
              onTap: onShare,
            ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.15),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PillButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  TEK GORSEL — zoom + pan + cift dokunus + asagi surukleyip kapatma.
/// ════════════════════════════════════════════════════════════════════
class _ZoomablePhoto extends StatefulWidget {
  final PhotoItem item;
  final String? heroTag;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePhoto({
    super.key,
    required this.item,
    required this.heroTag,
    required this.onTap,
    required this.onDismiss,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with TickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;

  // Asagi surukleyerek kapatma.
  double _dragDy = 0;
  bool _isDragging = false;

  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (_animation != null) _tc.value = _animation!.value;
      });
    _tc.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransformChanged);
    _tc.dispose();
    _animController.dispose();
    super.dispose();
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  void _onTransformChanged() {
    widget.onZoomChanged(_scale > 1.02);
  }

  void _animateTo(Matrix4 target) {
    _animation = Matrix4Tween(begin: _tc.value, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward(from: 0);
  }

  void _handleDoubleTap() {
    if (_scale > 1.02) {
      // Geri sifirla.
      _animateTo(Matrix4.identity());
    } else {
      // Dokunulan noktaya 3x zoom.
      final pos = _doubleTapDetails?.localPosition ??
          Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2,
          );
      const scale = 3.0;
      final x = -pos.dx * (scale - 1);
      final y = -pos.dy * (scale - 1);
      final target = Matrix4.identity()
        ..translate(x, y)
        ..scale(scale);
      _animateTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Surukleme miktarina gore kucult + soluklas.
    final dragScale = (1 - (_dragDy.abs() / size.height) * 0.4).clamp(0.6, 1.0);
    final dragOpacity =
        (1 - (_dragDy.abs() / (size.height * 0.5))).clamp(0.0, 1.0);

    // Devasa orijinal foto yerine ekran cozunurlugunde decode et.
    // Zoom 5x icin ekran genisliginin ~2 kati yeterli netlik verir.
    final decodeWidth = (size.width * dpr * 2).round();

    Widget image = Image(
      image: ResizeImage(widget.item.provider, width: decodeWidth),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_rounded,
            color: Colors.white38, size: 72),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        );
      },
    );

    if (widget.heroTag != null) {
      image = Hero(tag: widget.heroTag!, child: image);
    }

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: _handleDoubleTap,
      // Asagi surukleyip kapatma — sadece zoom yokken.
      onVerticalDragStart: _scale <= 1.02
          ? (_) => setState(() => _isDragging = true)
          : null,
      onVerticalDragUpdate: _scale <= 1.02 && _isDragging
          ? (d) => setState(() => _dragDy += d.delta.dy)
          : null,
      onVerticalDragEnd: _scale <= 1.02 && _isDragging
          ? (_) {
              if (_dragDy.abs() > 140) {
                widget.onDismiss();
              } else {
                setState(() {
                  _dragDy = 0;
                  _isDragging = false;
                });
              }
            }
          : null,
      child: Opacity(
        opacity: _isDragging ? dragOpacity : 1.0,
        child: Transform.translate(
          offset: Offset(0, _dragDy),
          child: Transform.scale(
            scale: _isDragging ? dragScale : 1.0,
            child: InteractiveViewer(
              transformationController: _tc,
              minScale: 1.0,
              maxScale: 5.0,
              clipBehavior: Clip.none,
              child: Center(child: image),
            ),
          ),
        ),
      ),
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  API — eski imzalar korundu (mevcut cagrilar bozulmasin).
/// ════════════════════════════════════════════════════════════════════

/// Tek gorseli tam ekran acar.
Future<void> openImageZoom(
  BuildContext context, {
  String? networkUrl,
  String? filePath,
  String? heroTag,
  String? title,
}) {
  if (networkUrl == null && filePath == null) return Future.value();
  return Navigator.of(context).push(_buildRoute(
    items: [
      PhotoItem(networkUrl: networkUrl, filePath: filePath, title: title),
    ],
    heroTag: heroTag,
  ));
}

/// Birden cok gorseli galeri olarak acar.
Future<void> openPhotoGallery(
  BuildContext context, {
  required List<PhotoItem> items,
  int initialIndex = 0,
  String? heroTag,
}) {
  final valid = items.where((e) => e.isValid).toList();
  if (valid.isEmpty) return Future.value();
  return Navigator.of(context).push(_buildRoute(
    items: valid,
    initialIndex: initialIndex,
    heroTag: heroTag,
  ));
}

PageRouteBuilder _buildRoute({
  required List<PhotoItem> items,
  int initialIndex = 0,
  String? heroTag,
}) {
  return PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => PhotoViewerScreen(
      items: items,
      initialIndex: initialIndex,
      heroTag: heroTag,
    ),
    transitionsBuilder: (_, anim, __, child) {
      // Sadece fade — hafif ve takilmasiz acilis.
      return FadeTransition(opacity: anim, child: child);
    },
  );
}

/// Geriye donuk uyumluluk: eski ImageZoomScreen adi.
class ImageZoomScreen extends StatelessWidget {
  final String? networkUrl;
  final String? filePath;
  final String? heroTag;
  final String? title;

  const ImageZoomScreen({
    super.key,
    this.networkUrl,
    this.filePath,
    this.heroTag,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return PhotoViewerScreen(
      items: [
        PhotoItem(networkUrl: networkUrl, filePath: filePath, title: title),
      ],
      heroTag: heroTag,
    );
  }
}

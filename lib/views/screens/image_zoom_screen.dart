import 'dart:io';
import 'dart:ui' as ui;

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
///  SİNEMATİK FOTOĞRAF GÖRÜNTÜLEYİCİ
///  Tamamen ozel — hicbir dis goruntuleyici paketi yok.
///
///  • Her fotodan ornekklenen baskin renkle canli ambient gradyan arka plan
///  • Spring (yaylanma) fizigi ile acilis ve kontrol animasyonlari
///  • Pinch-zoom (odakli) + pan + cift dokunus akilli zoom
///  • Asagi surukleyerek kapatma (kose yuvarlanir, kuculur, soluklasir)
///  • Glassmorphic ust bar + alt aksiyon cubugu (hafif, performansli blur)
///  • Film seridi thumbnail galerisi + animasyonlu sayfa noktalari
///  • Zoom seviyesi rozeti, mikro etkilesim animasyonlari
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

class _PhotoViewerScreenState extends State<PhotoViewerScreen>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _controlsCtrl;
  late int _index;
  bool _controlsVisible = true;
  bool _zoomedOnCurrent = false;
  double _bgDim = 0; // surukleme sirasinda arka plan kararmasi

  // Her foto icin baskin renk (ambient gradyan).
  final Map<int, Color> _accentByIndex = {};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _index);
    _controlsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      value: 1,
    );
    _extractAccent(_index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _controlsCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Fotodan baskin rengi cikar (kucuk cozunurlukte, performansli).
  Future<void> _extractAccent(int i) async {
    if (_accentByIndex.containsKey(i)) return;
    try {
      final provider = ResizeImage(widget.items[i].provider, width: 16);
      final stream = provider.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      listener = ImageStreamListener((info, _) async {
        stream.removeListener(listener); // tek sefer
        final img = info.image;
        final data =
            await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return;
        final bytes = data.buffer.asUint8List();
        int r = 0, g = 0, b = 0, count = 0;
        for (int p = 0; p < bytes.length; p += 4) {
          final cr = bytes[p], cg = bytes[p + 1], cb = bytes[p + 2];
          final lum = (cr + cg + cb) / 3;
          if (lum < 25 || lum > 235) continue;
          r += cr;
          g += cg;
          b += cb;
          count++;
        }
        if (count == 0) return;
        var color = Color.fromARGB(255, (r / count).round(),
            (g / count).round(), (b / count).round());
        final hsl = HSLColor.fromColor(color);
        color = hsl
            .withSaturation((hsl.saturation + 0.25).clamp(0.0, 1.0))
            .withLightness((hsl.lightness).clamp(0.25, 0.55))
            .toColor();
        if (mounted) setState(() => _accentByIndex[i] = color);
      });
      stream.addListener(listener);
    } catch (_) {}
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _controlsCtrl.forward();
    } else {
      _controlsCtrl.reverse();
    }
  }

  void _hideControls() {
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
      _controlsCtrl.reverse();
    }
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _share() async {
    final item = widget.items[_index];
    if (item.filePath != null && File(item.filePath!).existsSync()) {
      await Share.shareXFiles([XFile(item.filePath!)]);
    } else if (item.networkUrl != null) {
      await Share.share(item.networkUrl!);
    }
  }

  void _goToPage(int i) {
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final hasShare = item.isValid;
    final multiple = widget.items.length > 1;
    final accent = _accentByIndex[_index] ?? const Color(0xFF3D4BD4);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Canli ambient gradyan arka plan (foto rengine gore) ──
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.3,
                  colors: [
                    Color.lerp(accent, Colors.black, 0.45 + _bgDim * 0.4)!,
                    Color.lerp(accent, Colors.black, 0.78 + _bgDim * 0.2)!,
                    Colors.black,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // ── Gorsel galerisi ──
          PageView.builder(
            controller: _pageController,
            physics: _zoomedOnCurrent
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.items.length,
            onPageChanged: (i) {
              setState(() {
                _index = i;
                _zoomedOnCurrent = false;
              });
              _extractAccent(i);
            },
            itemBuilder: (context, i) {
              return _ZoomablePhoto(
                key: ValueKey('zoom_$i'),
                item: widget.items[i],
                heroTag: (widget.heroTag != null && i == widget.initialIndex)
                    ? widget.heroTag
                    : null,
                onTap: _toggleControls,
                onInteractStart: _hideControls,
                onDismiss: _close,
                onZoomChanged: (z) {
                  if (z != _zoomedOnCurrent) {
                    setState(() => _zoomedOnCurrent = z);
                  }
                },
                onDragDim: (v) => setState(() => _bgDim = v),
              );
            },
          ),

          // ── Ust bar (glassmorphic) ──
          _AnimatedBar(
            controller: _controlsCtrl,
            alignment: Alignment.topCenter,
            fromTop: true,
            child: _TopBar(
              title: multiple
                  ? '${_index + 1} / ${widget.items.length}'
                  : (item.title ?? ''),
              accent: accent,
              onClose: _close,
            ),
          ),

          // ── Alt: film seridi + aksiyonlar (glassmorphic) ──
          _AnimatedBar(
            controller: _controlsCtrl,
            alignment: Alignment.bottomCenter,
            fromTop: false,
            child: _BottomBar(
              items: widget.items,
              activeIndex: _index,
              accent: accent,
              showShare: hasShare,
              onShare: _share,
              onThumbTap: _goToPage,
            ),
          ),
        ],
      ),
    );
  }
}

/// ── Spring ile gelen/giden bar sarmalayici ───────────────────────────
class _AnimatedBar extends StatelessWidget {
  final AnimationController controller;
  final Alignment alignment;
  final bool fromTop;
  final Widget child;

  const _AnimatedBar({
    required this.controller,
    required this.alignment,
    required this.fromTop,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: Offset(0, fromTop ? -1 : 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    return Align(
      alignment: alignment,
      child: SlideTransition(
        position: slide,
        child: FadeTransition(opacity: controller, child: child),
      ),
    );
  }
}

/// ── Glassmorphic ust bar ──────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final Color accent;
  final VoidCallback onClose;
  const _TopBar(
      {required this.title, required this.accent, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            bottom: 14,
            left: 10,
            right: 10,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.45),
                Colors.black.withOpacity(0.0),
              ],
            ),
          ),
          child: Row(
            children: [
              _GlassCircleButton(
                  icon: Icons.arrow_back_ios_new_rounded, onTap: onClose),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    shadows: [Shadow(blurRadius: 10, color: Colors.black54)],
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Glassmorphic alt cubuk: film seridi + paylas ─────────────────────
class _BottomBar extends StatelessWidget {
  final List<PhotoItem> items;
  final int activeIndex;
  final Color accent;
  final bool showShare;
  final VoidCallback onShare;
  final ValueChanged<int> onThumbTap;

  const _BottomBar({
    required this.items,
    required this.activeIndex,
    required this.accent,
    required this.showShare,
    required this.onShare,
    required this.onThumbTap,
  });

  @override
  Widget build(BuildContext context) {
    final multiple = items.length > 1;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            top: 18,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withOpacity(0.5),
                Colors.black.withOpacity(0.0),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Film seridi (coklu gorselse).
              if (multiple) ...[
                SizedBox(
                  height: 62,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final active = i == activeIndex;
                      return GestureDetector(
                        onTap: () => onThumbTap(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          width: active ? 62 : 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: active ? accent : Colors.white24,
                              width: active ? 2.5 : 1,
                            ),
                            boxShadow: active
                                ? [
                                    BoxShadow(
                                      color: accent.withOpacity(0.5),
                                      blurRadius: 12,
                                      spreadRadius: 1,
                                    )
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Opacity(
                              opacity: active ? 1 : 0.55,
                              child: Image(
                                image: ResizeImage(items[i].provider,
                                    width: 130),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.white10,
                                  child: const Icon(Icons.image_not_supported,
                                      color: Colors.white30, size: 18),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (showShare)
                _GlassPillButton(
                  icon: Icons.ios_share_rounded,
                  label: 'Paylaş',
                  accent: accent,
                  onTap: onShare,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Dokununca olceklenen cam yuvarlak buton ──────────────────────────
class _GlassCircleButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassCircleButton({required this.icon, required this.onTap});

  @override
  State<_GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<_GlassCircleButton> {
  double _scale = 1;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.85),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Icon(widget.icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// ── Dokununca olceklenen cam pill buton ──────────────────────────────
class _GlassPillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _GlassPillButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_GlassPillButton> createState() => _GlassPillButtonState();
}

class _GlassPillButtonState extends State<_GlassPillButton> {
  double _scale = 1;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.93),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              widget.accent.withOpacity(0.85),
              widget.accent.withOpacity(0.6),
            ]),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withOpacity(0.45),
                blurRadius: 16,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(widget.label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
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
  final VoidCallback onInteractStart;
  final VoidCallback onDismiss;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<double> onDragDim;

  const _ZoomablePhoto({
    super.key,
    required this.item,
    required this.heroTag,
    required this.onTap,
    required this.onInteractStart,
    required this.onDismiss,
    required this.onZoomChanged,
    required this.onDragDim,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with TickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;

  double _dragDy = 0;
  bool _isDragging = false;
  bool _showZoomBadge = false;
  double _currentScale = 1.0;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
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
    final s = _scale;
    widget.onZoomChanged(s > 1.02);
    if ((s - _currentScale).abs() > 0.01) {
      setState(() {
        _currentScale = s;
        _showZoomBadge = s > 1.05;
      });
    }
  }

  void _animateTo(Matrix4 target) {
    _animation = Matrix4Tween(begin: _tc.value, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward(from: 0);
  }

  void _handleDoubleTap() {
    if (_scale > 1.02) {
      _animateTo(Matrix4.identity());
    } else {
      final pos = _doubleTapDetails?.localPosition ??
          Offset(MediaQuery.of(context).size.width / 2,
              MediaQuery.of(context).size.height / 2);
      const scale = 2.8;
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
    final dragScale =
        (1 - (_dragDy.abs() / size.height) * 0.35).clamp(0.7, 1.0);
    final dragOpacity =
        (1 - (_dragDy.abs() / (size.height * 0.6))).clamp(0.0, 1.0);
    final dragRadius = (_dragDy.abs() / 12).clamp(0.0, 28.0);

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
        return Center(
          child: SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white.withOpacity(0.7),
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
    );

    if (widget.heroTag != null) {
      image = Hero(tag: widget.heroTag!, child: image);
    }

    return Stack(
      children: [
        GestureDetector(
          onTap: widget.onTap,
          onDoubleTapDown: (d) => _doubleTapDetails = d,
          onDoubleTap: _handleDoubleTap,
          onVerticalDragStart: _scale <= 1.02
              ? (_) {
                  widget.onInteractStart();
                  setState(() => _isDragging = true);
                }
              : null,
          onVerticalDragUpdate: _scale <= 1.02 && _isDragging
              ? (d) {
                  setState(() => _dragDy += d.delta.dy);
                  widget.onDragDim(
                      (_dragDy.abs() / (size.height * 0.5)).clamp(0.0, 1.0));
                }
              : null,
          onVerticalDragEnd: _scale <= 1.02 && _isDragging
              ? (_) {
                  if (_dragDy.abs() > 130) {
                    widget.onDismiss();
                  } else {
                    setState(() {
                      _dragDy = 0;
                      _isDragging = false;
                    });
                    widget.onDragDim(0);
                  }
                }
              : null,
          child: Opacity(
            opacity: _isDragging ? dragOpacity : 1.0,
            child: Transform.translate(
              offset: Offset(0, _dragDy),
              child: Transform.scale(
                scale: _isDragging ? dragScale : 1.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(dragRadius),
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
          ),
        ),

        // ── Zoom seviyesi rozeti ──
        Positioned(
          top: MediaQuery.of(context).padding.top + 70,
          right: 16,
          child: AnimatedOpacity(
            opacity: _showZoomBadge ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '${_currentScale.toStringAsFixed(1)}x',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  API — eski imzalar korundu (mevcut cagrilar bozulmasin).
/// ════════════════════════════════════════════════════════════════════

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
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => PhotoViewerScreen(
      items: items,
      initialIndex: initialIndex,
      heroTag: heroTag,
    ),
    transitionsBuilder: (_, anim, __, child) {
      // Spring hissi veren yumusak fade + hafif yukselme.
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Geriye donuk uyumluluk.
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

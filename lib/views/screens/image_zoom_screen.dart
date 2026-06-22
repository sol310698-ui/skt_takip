import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';

/// ════════════════════════════════════════════════════════════════════
///  GORSEL GORUNTULEYICI — photo_view paketi ile.
///
///  Eskiden bu ekran tamamen elle yazilmis ozel animasyon/blur/renk-
///  ornekleme koduyla (885 satir) yapiliyordu; bu agir is yuku dusuk/orta
///  segment cihazlarda kasmaya yol aciyordu. Simdi pinch-zoom, pan, cift
///  dokunus zoom ve sayfa gecisleri olgun ve performansli bir kutuphane
///  (photo_view) tarafindan yonetiliyor. Kendi tasarimimiz (AppBar,
///  Paylas butonu, Hero gecisi) ustte ince bir katman olarak kaldi.
///
///  Bir gorsel kaynagi: ag URL'si veya yerel dosya yolu.
/// ════════════════════════════════════════════════════════════════════
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

/// Tek veya coklu gorsel goruntuleyici. photo_view ile pinch/pan/double-tap
/// zoom; coklu gorselde PhotoViewGallery ile sayfalar arasi kaydirma.
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
  late int _index;
  late final PageController _pageController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_busy) return;
    final item = widget.items[_index];
    setState(() => _busy = true);
    try {
      if (item.filePath != null && await File(item.filePath!).exists()) {
        await Share.shareXFiles([XFile(item.filePath!)]);
      } else if (item.networkUrl != null) {
        await Share.share(item.networkUrl!);
      }
    } catch (_) {
      // Paylasim iptal/hata: sessizce gec, kullanici tekrar deneyebilir.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _currentTitle => widget.items[_index].title;

  @override
  Widget build(BuildContext context) {
    final multiple = widget.items.length > 1;
    final item = widget.items[_index];
    final hasShare = item.isValid;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.35),
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: _currentTitle != null
            ? Text(
                _currentTitle!,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              )
            : null,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: multiple
                ? _buildGallery()
                : _buildSingle(item, widget.heroTag),
          ),
          if (multiple)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(
                    child: _PageDots(
                      count: widget.items.length,
                      index: _index,
                    ),
                  ),
                ),
              ),
            ),
          if (hasShare)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 8),
                  child: Center(
                    child: _ShareButton(busy: _busy, onTap: _share),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSingle(PhotoItem item, String? heroTag) {
    return PhotoView(
      imageProvider: item.provider,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3,
      heroAttributes: heroTag != null
          ? PhotoViewHeroAttributes(tag: heroTag)
          : null,
      loadingBuilder: (context, event) => const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      ),
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.broken_image_rounded,
            color: Colors.white30, size: 48),
      ),
    );
  }

  Widget _buildGallery() {
    return PhotoViewGallery.builder(
      pageController: _pageController,
      itemCount: widget.items.length,
      onPageChanged: (i) => setState(() => _index = i),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (context, event) => const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      ),
      builder: (context, i) {
        final it = widget.items[i];
        return PhotoViewGalleryPageOptions(
          imageProvider: it.provider,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image_rounded,
                color: Colors.white30, size: 48),
          ),
        );
      },
    );
  }
}

/// Sayfa noktalari (coklu gorselde hangi sayfadayiz gostergesi).
class _PageDots extends StatelessWidget {
  final int count;
  final int index;
  const _PageDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 8 : 6,
          height: active ? 8 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.white : Colors.white38,
          ),
        );
      }),
    );
  }
}

/// Alt ortadaki "Paylaş" pill butonu.
class _ShareButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _ShareButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.14),
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              else
                const Icon(Icons.ios_share_rounded,
                    color: Colors.white, size: 19),
              const SizedBox(width: 10),
              const Text(
                'Paylaş',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
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
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => PhotoViewerScreen(
      items: items,
      initialIndex: initialIndex,
      heroTag: heroTag,
    ),
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      return FadeTransition(opacity: curved, child: child);
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

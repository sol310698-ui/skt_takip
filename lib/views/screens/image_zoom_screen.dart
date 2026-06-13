import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Bir gorsel kaynagi: ya ag URL'si ya yerel dosya yolu.
class PhotoItem {
  final String? networkUrl;
  final String? filePath;
  final String? title;
  const PhotoItem({this.networkUrl, this.filePath, this.title});

  bool get isValid => networkUrl != null || filePath != null;
}

/// Modern tam ekran fotograf goruntuleyici (photo_view tabanli).
/// Pinch-zoom, cift dokunus zoom, kaydirarak gezinme, asagi kaydirip kapatma.
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
  late final PageController _controller;
  late int _current;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.items.length - 1);
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ImageProvider _provider(PhotoItem item) {
    if (item.networkUrl != null) {
      return CachedNetworkImageProvider(item.networkUrl!);
    }
    return FileImage(File(item.filePath!));
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.items.length > 1;
    final title =
        widget.items.isNotEmpty ? widget.items[_current].title : null;
    final bgOpacity = (1 - (_dragOffset.abs() / 400)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(bgOpacity),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          multiple ? '${_current + 1} / ${widget.items.length}' : (title ?? ''),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: GestureDetector(
        onVerticalDragUpdate: (d) {
          setState(() => _dragOffset += d.delta.dy);
        },
        onVerticalDragEnd: (_) {
          if (_dragOffset.abs() > 120) {
            Navigator.of(context).maybePop();
          } else {
            setState(() => _dragOffset = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: PhotoViewGallery.builder(
            pageController: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _current = i),
            backgroundDecoration:
                const BoxDecoration(color: Colors.transparent),
            scrollPhysics: multiple
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            builder: (context, index) {
              final item = widget.items[index];
              return PhotoViewGalleryPageOptions(
                imageProvider: _provider(item),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                initialScale: PhotoViewComputedScale.contained,
                heroAttributes: (widget.heroTag != null && index == _current)
                    ? PhotoViewHeroAttributes(tag: widget.heroTag!)
                    : null,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_rounded,
                      color: Colors.white38, size: 64),
                ),
              );
            },
            loadingBuilder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tek gorseli tam ekran acar. Eski openImageZoom imzasiyla uyumlu.
Future<void> openImageZoom(
  BuildContext context, {
  String? networkUrl,
  String? filePath,
  String? heroTag,
  String? title,
}) {
  if (networkUrl == null && filePath == null) return Future.value();
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => PhotoViewerScreen(
        items: [
          PhotoItem(networkUrl: networkUrl, filePath: filePath, title: title),
        ],
        heroTag: heroTag,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
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
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => PhotoViewerScreen(
        items: valid,
        initialIndex: initialIndex,
        heroTag: heroTag,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// Geriye donuk uyumluluk: eski ImageZoomScreen adiyla cagiranlar icin.
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

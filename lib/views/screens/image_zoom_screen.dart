import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

import '../widgets/ui_kit.dart';

/// Tam ekran, yakinlastirilabilir gorsel goruntuleyici.
/// Hem ag (network) hem yerel dosya (file) gorsellerini destekler.
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
    Widget image;
    if (networkUrl != null) {
      image = CachedImage(
        url: networkUrl!,
        fit: BoxFit.contain,
        placeholder: _err,
      );
    } else if (filePath != null) {
      image = Image.file(
        File(filePath!),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _err(),
      );
    } else {
      image = _err();
    }

    if (heroTag != null) {
      image = Hero(tag: heroTag!, child: image);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: title != null ? Text(title!) : null,
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: image,
          ),
        ),
      ),
    );
  }

  Widget _err() => const Center(
        child: Icon(Icons.broken_image_rounded,
            color: Colors.white38, size: 64),
      );
}

/// Yardimci: bir gorsele dokununca zoom ekranina gec.
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
      pageBuilder: (_, __, ___) => ImageZoomScreen(
        networkUrl: networkUrl,
        filePath: filePath,
        heroTag: heroTag,
        title: title,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

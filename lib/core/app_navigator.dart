import 'package:flutter/material.dart';

/// Global navigator anahtari.
///
/// Cekirdek katmanda durur ki servisler (alarm akisi, asistan gezinme)
/// uygulamanin giris dosyasina (main.dart) bagimli olmadan ekran acabilsin.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

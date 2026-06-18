import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

/// Alt navigasyon barinin gorunurlugunu yoneten global notifier.
///
/// Listelerin scroll yonune gore (asagi kaydir -> gizle, yukari -> goster)
/// guncellenir. MainShell bunu dinler ve nav bar'i animasyonla gizler/gosterir.
final ValueNotifier<bool> navBarVisible = ValueNotifier<bool>(true);

/// Bir ScrollController'in yonune gore nav bar gorunurlugunu gunceller.
/// Ekranlarda tek satirla baglamak icin yardimci.
void handleNavBarScroll(ScrollController controller) {
  if (!controller.hasClients) return;
  final dir = controller.position.userScrollDirection;
  if (dir == ScrollDirection.reverse && navBarVisible.value) {
    navBarVisible.value = false;
  } else if (dir == ScrollDirection.forward && !navBarVisible.value) {
    navBarVisible.value = true;
  }
}

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// ════════════════════════════════════════════════════════════════════
///  KAMERA YASAM DONGUSU MIXIN'i
/// ────────────────────────────────────────────────────────────────────
///  Sorun: mobile_scanner, kamera KESINTIYE ugradiginda (uygulama arka
///  plana gitti, ekran kilitlendi, bildirim geldi, ya da uygulamanin kendisi
///  sistem kamerasini/foto cekimini actii) kendini otomatik toparlamiyor;
///  "hata" durumuna dusup EKRANDA UNLEM/UYARI ikonu gosteriyor. Cogu ekran
///  one donunce kamerayi yeniden baslatmadigi icin bu durumda takili kaliyor
///  (elle ac/kapat yapinca duzeliyordu).
///
///  Bu mixin: uygulama DURAKLAYINCA kamerayi durdurur, ONE DONUNCE yeniden
///  baslatir. Boylece unlem/takilma olusmaz. Ekran yalnizca
///  [cameraControllers] getter'ini saglar (nullable controller'lar icin
///  filtreli liste dondurun). Gerekirse [shouldResumeCamera] ile resume'da
///  baslatmayi kosullandirin (orn. oturum tamamlandiysa false).
///
///  Kullanim:
///    class _FooState extends State<Foo> with CameraLifecycleMixin {
///      final _controller = MobileScannerController();
///      @override
///      List<MobileScannerController> get cameraControllers => [_controller];
///      ...
///    }
///
///  NOT: Ekranin initState/dispose'u super.initState()/super.dispose()
///  cagirdigi surece mixin otomatik devreye girer (kod tabaninda hepsi
///  cagiriyor).
/// ════════════════════════════════════════════════════════════════════
mixin CameraLifecycleMixin<T extends StatefulWidget> on State<T> {
  late final _CamLifecycleObserver _camObserver =
      _CamLifecycleObserver(_handleCamLifecycle);

  /// Yonetilecek kamera controller'lari. Nullable/lazy controller'lar icin
  /// filtreli liste dondurun: `[if (_scanner != null) _scanner!]`.
  List<MobileScannerController> get cameraControllers;

  /// One donunce kamera yeniden baslatilsin mi? Varsayilan: evet.
  bool get shouldResumeCamera => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_camObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_camObserver);
    super.dispose();
  }

  void _handleCamLifecycle(AppLifecycleState state) {
    final resume = state == AppLifecycleState.resumed;
    final pause = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden;
    if (!resume && !pause) return;
    for (final c in cameraControllers) {
      if (pause) {
        try {
          c.stop();
        } catch (_) {}
      } else if (resume && shouldResumeCamera) {
        try {
          c.start();
        } catch (_) {}
      }
    }
  }
}

/// Ic gozlemci — mixin'in State'e WidgetsBindingObserver eklemesini
/// (ve tum arayuz metodlarini uygulamasini) zorunlu kilmadan calisir.
class _CamLifecycleObserver extends WidgetsBindingObserver {
  final void Function(AppLifecycleState) onState;
  _CamLifecycleObserver(this.onState);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onState(state);
}

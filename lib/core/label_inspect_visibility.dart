import 'package:flutter/foundation.dart';

/// Etiket İncele butonu artık TÜM sayfalarda goruntuleniyor (global overlay,
/// bkz. main.dart). Ancak kullanici zaten Etiket Incele ekranindaysa ayni
/// butonu tekrar gostermenin anlami yok - LabelInspectScreen acilinca bunu
/// true yapar, kapaninca false'a doner.
final ValueNotifier<bool> labelInspectFabSuppressed = ValueNotifier<bool>(false);

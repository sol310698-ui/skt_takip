# ════════════════════════════════════════════════════════════════════
#  PROGUARD / R8 KURALLARI — Tersine muhendisligi zorlastirmak icin
# ────────────────────────────────────────────────────────────────────
#  Bu dosya minifyEnabled=true oldugunda devreye girer. R8, kullanilmayan
#  kodu siler ve KALAN kodun sinif/metod/alan adlarini kisa, anlamsiz
#  isimlere (a, b, c...) cevirir (obfuscation). Bu, APK'yi decompile eden
#  birinin okunabilir bir kaynak kodu yerine anlamsiz isimler gormesini
#  saglar — mantigi anlamak COK daha zor ve zaman alici hale gelir.
#
#  "keep" kurallari: R8'in DOKUNMAMASI gereken siniflari belirtir.
#  Flutter engine, plugin'lerin native koprusu (MethodChannel/EventChannel
#  reflection ile cagrildigi icin) ve bazi kutuphaneler (sqflite, JSON
#  serileştirme vb.) bu kurallar olmadan obfuscation sonrasi CRASH eder.
#  Asiri "keep" yazmak obfuscation'i etkisiz kilar; bu dosya SADECE
#  gerekli olanlari tutacak sekilde dar tutulmustur.
# ════════════════════════════════════════════════════════════════════

# ── Flutter cekirdegi ──
# Flutter engine'in JNI/reflection ile erisecegi siniflar. Bunlar
# olmadan uygulama beyaz ekranda kalir veya aninda crash eder.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# ── Uygulamanin kendi native (Kotlin) koprusu ──
# MainActivity, PriceAccessibilityService ve BootReceiver MethodChannel/
# EventChannel/AccessibilityService API'leri uzerinden Android sistemi
# tarafindan REFLECTION ile cagrilir (manifest'teki sinif adlariyla
# eslesir). Bu siniflarin adi/yapisi degismemeli, aksi halde Android
# servisi/Activity'yi bulamaz ve uygulama acilamaz hale gelir.
-keep class com.example.skt_takip.MainActivity { *; }
-keep class com.example.skt_takip.PriceAccessibilityService { *; }
-keep class com.example.skt_takip.BootReceiver { *; }
-keep class com.example.skt_takip.KeepAliveService { *; }

# ── sqflite (SQLite) ──
-keep class com.tekartik.sqflite.** { *; }

# ── google_mlkit_text_recognition / ML Kit ──
# ML Kit, model dosyalarini ve islem siniflarini reflection ile yukler.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-dontwarn com.google.mlkit.**

# ── mobile_scanner / camera / Google Play Services (barkod + kamera) ──
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class androidx.camera.** { *; }
-dontwarn com.google.android.gms.**

# ── geolocator ──
-keep class com.baseflow.geolocator.** { *; }

# ── local_auth (biyometri) ──
-keep class io.flutter.plugins.localauth.** { *; }
-keep class androidx.biometric.** { *; }

# ── flutter_local_notifications ──
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers class * extends android.app.Notification { *; }

# ── alarm paketi (gdelataillade) ──
-keep class com.gdelataillade.alarm.** { *; }

# ── flutter_secure_storage (Android Keystore) ──
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }

# ── permission_handler ──
-keep class com.baseflow.permissionhandler.** { *; }

# ── webview_flutter ──
-keep class io.flutter.plugins.webviewflutter.** { *; }

# ── JSON / Gson benzeri reflection kullanan kutuphaneler icin genel
#    guvenlik (modeller @SerializedName veya benzeri kullaniyorsa adi
#    degismesin diye; projede kullanilan model siniflari kucuk oldugundan
#    genis bir kapsam yerine sadece data/models altini hedefliyoruz). ──
-keepclassmembers class com.example.skt_takip.** {
    <fields>;
}

# ── Kotlin metadata (Kotlin reflection kullanan kutuphaneler icin) ──
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlin.Metadata { *; }
-dontwarn kotlin.**

# ── Genel Android bilesenleri (manifest'te adi gecen her sey otomatik
#    korunur ama yine de aciklik olsun diye) ──
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# ── Enum'lar (R8 bazen enum'larin values()/valueOf() metodlarini
#    yanlislikla kaldirabilir; JSON/serialestirme icin guvenlik) ──
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── Satir numaralarini SAKLA (crash raporlarini okunabilir tutmak icin) ──
# Sinif/metod adlari obfuscate olsa da hangi satirda crash oldugunu
# gormek hata ayiklamayi kolaylastirir; tersine muhendislige katkisi yok.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ── Anotasyonlari sakla (bazi kutuphaneler runtime'da anotasyon okur) ──
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ── Genel uyarilari sessize al (eksik/optional siniflar icin) ──
-dontwarn javax.annotation.**
-dontwarn org.slf4j.**

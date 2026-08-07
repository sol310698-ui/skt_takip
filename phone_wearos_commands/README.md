# phone-wearos-commands

Telefon (Android) ile **Wear OS** saat arasinda **komut gonderip alma** yapan
ornek uygulama. Iletisim, Google'in resmi **Wearable Data Layer API**'si
(`MessageClient`) uzerinden yapilir — internet/sunucu gerekmez, cihazlar
Bluetooth/Wi-Fi ile eslesince dogrudan haberlesir.

> Not: Bu proje ilk olarak `skt_takip` deposu icinde `phone_wearos_commands/`
> klasoru olarak olusturuldu. Kendi deposuna tasindiginda bu klasoru repo koku
> yapman yeterli — Gradle ve GitHub Actions ayarlari buna gore hazir.

## Mimari

Uc Gradle modulu:

| Modul     | Nedir                                                        |
|-----------|-------------------------------------------------------------|
| `shared`  | Ortak kod: komut sozlesmesi, gonderici, dinleyici servis    |
| `mobile`  | Telefon uygulamasi (UI: PING / VIBRATE / ozel komut)        |
| `wear`    | Wear OS saat uygulamasi (UI: PING / VIBRATE / HELLO)        |

`mobile` ve `wear` **ayni `applicationId`** (`com.example.wearcommands`)
kullanir — Data Layer eslesmesi ancak bu sekilde kurulur.

### Komut akisi

```
[Telefon UI] --(MessageClient: "/command", "PING")--> [Saat]
                                                         |
                                    CommandListenerService alir
                                                         |
                            CommandBus -> ekrana yaz + otomatik PONG cevabi
                                                         |
[Telefon] <--(MessageClient: "/command", "PONG")---------
```

- **Gonderme:** `CommandSender.send(context, "PING")` bagli tum node'lara mesaj yollar.
- **Alma:** `CommandListenerService.onMessageReceived(...)` calisir (uygulama
  kapali olsa bile Play Services servisi baslatir), komutu `CommandBus`'a yayar.
- **Otomatik tepki:** `PING` -> karsi tarafa `PONG`; `VIBRATE` -> cihazi titretir.

### Onemli dosyalar

| Dosya | Gorevi |
|-------|--------|
| `shared/.../CommandProtocol.kt`        | Yol (`/command`) ve komut sabitleri |
| `shared/.../CommandSender.kt`          | Bagli cihazlara mesaj gonderme |
| `shared/.../CommandListenerService.kt` | Gelen mesaji dinleme + otomatik tepki |
| `shared/.../CommandBus.kt`             | Servis -> Activity ic olay yolu |
| `mobile/.../MainActivity.kt`           | Telefon arayuzu |
| `wear/.../MainActivity.kt`             | Saat arayuzu |

## Yeni komut ekleme

1. `CommandProtocol.kt` icine sabiti ekle (or. `const val CMD_FLASH = "FLASH"`).
2. Gondermek icin bir butona `send(CommandProtocol.CMD_FLASH)` bagla.
3. Otomatik tepki istiyorsan `CommandListenerService.onMessageReceived`
   icindeki `when` blocuna ekle.

## Derleme ve calistirma

Gereksinim: Android Studio (Hedgehog+), JDK 17, bir Wear OS emulatoru veya saat.

```bash
# Wrapper yoksa bir kez olustur:
gradle wrapper --gradle-version 8.7

# APK'lari derle:
./gradlew :mobile:assembleDebug :wear:assembleDebug
```

Test icin en kolay yol: Android Studio'da bir **telefon emulatoru** ve bir
**Wear OS emulatoru** ac, ikisini esle (`adb`  ile Wear eslestirme), her iki
uygulamayi da kur ve butonlara bas.

## Lisans

Ornek/baslangic projesi — diledigin gibi kullanabilirsin.

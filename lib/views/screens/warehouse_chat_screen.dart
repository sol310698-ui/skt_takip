import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/services/assistant_action_service.dart';
import '../../core/services/gemini_ocr_service.dart';
import '../../core/services/price_check_channel.dart';
import '../../core/services/warehouse_assistant_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import '../../data/models/barcode_entry.dart';
import '../../data/repositories/barcode_directory_repository.dart';
import '../../core/services/agent_tool_service.dart';
import '../../core/services/database_service.dart';
import 'barcode_detail_screen.dart';
import 'add_product_screen.dart' show BarcodeScanPage;

/// ════════════════════════════════════════════════════════════════════
///  DEPO ASISTANI — SOHBET EKRANI
/// ────────────────────────────────────────────────────────────────────
///  Kullanici "pilavlık bulgur nerede?", "ketçaplar hangi reyonda?" gibi
///  sorular sorar. Asistan once telefondaki reyon verisinden cevaplar;
///  yetmezse internetten araştırır (Gemini + Google Arama).
/// ════════════════════════════════════════════════════════════════════
class WarehouseChatScreen extends StatefulWidget {
  const WarehouseChatScreen({super.key});

  @override
  State<WarehouseChatScreen> createState() => _WarehouseChatScreenState();
}

class _ChatMsg {
  final bool fromUser;
  String text;
  // Bu mesaja bagli asistan eylemleri (onay bekleyen ya da sonuclanmis).
  final List<AssistantAction> actions;
  // Her eylemin durumu: null=bekliyor, true=onaylandi/calisti, false=iptal.
  final List<bool?> actionStates;
  final List<String?> actionResults; // calisma sonrasi mesaj
  _ChatMsg(this.fromUser, this.text, {List<AssistantAction>? actions})
      : actions = actions ?? [],
        actionStates = List<bool?>.filled(actions?.length ?? 0, null),
        actionResults = List<String?>.filled(actions?.length ?? 0, null);
}

class _WarehouseChatScreenState extends State<WarehouseChatScreen> {
  // Agent hangi araclari kullaniyor (yazi yaziyor gostergesinde gorunur).
  String? _toolNote;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMsg> _messages = [];
  bool _sending = false;
  bool _hasKey = true;

  // ── SESLI MOD ──
  // Mikrofonla soru sor, cevabi sesli dinle. Acikken her cevap TTS ile
  // okunur; mikrofon butonu basili tutmadan tek dokunusla dinler.
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  bool _voiceMode = false; // cevaplar sesli okunsun mu
  String _partial = ''; // dinlerken canli metin

  @override
  void initState() {
    super.initState();
    _checkKey();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) return;
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechReady = ok);
    } catch (_) {}
  }

  /// Mikrofon: dinlemeyi baslat/durdur. Konusma bitince metin kutuya yazilir
  /// ve OTOMATIK gonderilir (eller serbest akis).
  Future<void> _toggleListen() async {
    if (!_speechReady) {
      await _initSpeech();
      if (!_speechReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Mikrofon kullanılamıyor. İzinleri kontrol edin.')));
        }
        return;
      }
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _listening = true;
      _voiceMode = true; // sesle soruldu -> sesle cevapla
      _partial = '';
    });
    await _speech.listen(
      localeId: 'tr_TR',
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.confirmation,
      ),
      pauseFor: const Duration(seconds: 2),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _partial = r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          _input.text = r.recognizedWords.trim();
          _listening = false;
          _send();
        }
      },
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _checkKey() async {
    final has = await GeminiOcrService.instance.hasApiKey();
    if (mounted) setState(() => _hasKey = has);
  }

  Future<void> _send() async {
    final q = _input.text.trim();
    if (q.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMsg(true, q));
      _sending = true;
      _toolNote = null;
      _input.clear();
    });
    _scrollToBottom();

    // Gemini'ye gonderilecek gecmis (son mesaj HARIC — o 'question' olarak
    // ayri gidiyor). Cok uzamasin diye son 10 mesaj.
    final history = <Map<String, String>>[];
    for (final m in _messages.take(_messages.length - 1).toList().reversed
        .take(10)
        .toList()
        .reversed) {
      history.add({'role': m.fromUser ? 'user' : 'model', 'text': m.text});
    }

    try {
      // AGENT DONGUSU: model gerekirse once araclarla kesif yapar
      // (sema, SQL okuma, ayar listeleme), sonra cevabini verir.
      final answer = await WarehouseAssistantService.instance.askAgent(
        history: history,
        question: q,
        onStep: (names) {
          if (mounted) setState(() => _toolNote = names);
        },
      );
      if (!mounted) return;
      // Once arac bloklarini (varsa artik), sonra eylem bloklarini ayikla.
      final toolStripped =
          AgentToolService.instance.parse(answer.trim()).cleanText;
      final parsed = AssistantActionService.instance
          .parse(toolStripped.isEmpty ? answer.trim() : toolStripped);
      final display = parsed.cleanText.isEmpty
          ? (parsed.actions.isEmpty ? answer.trim() : 'Onayınızı bekliyorum:')
          : parsed.cleanText;
      setState(() => _messages
          .add(_ChatMsg(false, display, actions: parsed.actions)));
      // Sesli moddaysa cevabi oku (mevcut native TTS ile).
      if (_voiceMode) {
        final speakText = display.length > 300
            ? '${display.substring(0, 300)}…'
            : display;
        await PriceCheckChannel.speak(speakText);
      }
    } on GeminiOcrException catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_ChatMsg(
          false,
          'Yanıt alınamadı: ${e.message}\n\n'
          'Ayarlar\'dan Gemini API anahtarınızı kontrol edin.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_ChatMsg(false, 'Bir hata oluştu: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _toolNote = null;
        });
      }
      _scrollToBottom();
    }
  }

  // ── EYLEM ONAYI ────────────────────────────────────────────────────
  /// Kullanici bir eylem kartinda "Onayla" der -> gercek islemi calistir.
  Future<void> _approveAction(_ChatMsg msg, int index) async {
    if (msg.actionStates[index] != null) return; // zaten islenmis
    HapticFeedback.mediumImpact();
    setState(() => msg.actionStates[index] = true);
    final result =
        await AssistantActionService.instance.execute(msg.actions[index]);
    if (!mounted) return;
    setState(() => msg.actionResults[index] = result);
    _scrollToBottom();
  }

  void _rejectAction(_ChatMsg msg, int index) {
    if (msg.actionStates[index] != null) return;
    HapticFeedback.lightImpact();
    setState(() {
      msg.actionStates[index] = false;
      msg.actionResults[index] = 'İptal edildi.';
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _hero(),
          if (!_hasKey) _keyWarning(),
          if (_listening) _listeningBar(),
          Expanded(
            child: _messages.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) return _typingBubble();
                      return _bubble(_messages[i]);
                    },
                  ),
          ),
          _composer(),
        ],
      ),
    );
  }

  /// GRADYAN HERO — uygulamanin diger ekranlariyla ayni tasarim dili
  /// (palet detay, reyona acilacaklar, teshir). Baslik + agent durumu +
  /// sesli yanit anahtari.
  Widget _hero() {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent,
            Color.lerp(AppTheme.accent, AppTheme.primary, 0.55)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
          ),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 19, color: Colors.black),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Depo Asistanı',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.black)),
                Text(
                  _sending
                      ? (_toolNote == null
                          ? 'düşünüyor…'
                          : 'araç: $_toolNote')
                      : 'sorar · bulur · onayınla yapar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: Colors.black87),
                ),
              ],
            ),
          ),
          // Sesli mod: acikken cevaplar TTS ile okunur.
          IconButton(
            tooltip: _voiceMode ? 'Sesli yanıt açık' : 'Sesli yanıt kapalı',
            onPressed: () => setState(() => _voiceMode = !_voiceMode),
            icon: Icon(
                _voiceMode
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                color: _voiceMode ? Colors.black : Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _keyWarning() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.statusWarning.withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border:
              Border.all(color: AppTheme.statusWarning.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.key_off_rounded,
                size: 17, color: AppTheme.statusWarning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Gemini API anahtarı ayarlı değil. Ayarlar\'dan girin.',
                style: TextStyle(
                    color: AppTheme.statusWarning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _emptyState() {
    final examples = <(IconData, String)>[
      (Icons.place_rounded, 'Pilavlık bulgur nerede?'),
      (Icons.add_box_rounded, 'P123 paletine 6 adet ketçap ekle'),
      (Icons.event_busy_rounded, 'Bu hafta SKT\'si dolan var mı?'),
      (Icons.insights_rounded, 'En dolu 5 paleti listele'),
      (Icons.tune_rounded, 'Temayı koyu yap'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 16),
      children: [
        // Ikon rozeti — uygulamadaki dairesel vurgu dili.
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.accent.withOpacity(0.22),
                  AppTheme.primary.withOpacity(0.18),
                ],
              ),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 34, color: AppTheme.accent),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Ne yapmamı istersin?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Ürün yerini sor, SKT kontrol et ya da işlem yaptır. '
          'Gerekirse verilerini kendim inceler, çözümü bulurum — '
          'her değişikliği senin onayınla yaparım.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.textTertiary, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('ÖRNEKLER',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: AppTheme.textTertiary)),
        ),
        // Oneriler: uygulamanin kart dili (surface + hairline + rMd).
        ...examples.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                onTap: () {
                  _input.text = e.$2;
                  _send();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                    border: Border.all(color: AppTheme.hairline),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.13),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(e.$1,
                            size: 17, color: AppTheme.accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.$2,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                      ),
                      Icon(Icons.north_east_rounded,
                          size: 15, color: AppTheme.textTertiary),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _bubble(_ChatMsg m) {
    final isUser = m.fromUser;
    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            decoration: BoxDecoration(
              color: isUser ? AppTheme.accent : AppTheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppTheme.rMd),
                topRight: const Radius.circular(AppTheme.rMd),
                bottomLeft: Radius.circular(isUser ? AppTheme.rMd : 4),
                bottomRight: Radius.circular(isUser ? 4 : AppTheme.rMd),
              ),
              border: isUser ? null : Border.all(color: AppTheme.hairline),
            ),
            child: isUser
                // Accent zeminde SIYAH yazi — uygulamanin accent buton
                // dili (beyaz yazi acik turkuazda okunmuyordu).
                ? SelectableText(
                    m.text,
                    style: const TextStyle(
                        color: Colors.black, fontSize: 14.5, height: 1.3),
                  )
                : _richAssistantText(m.text),
          ),
        ),
        // Onay kartlari (asistan mesajina bagli eylemler).
        for (int i = 0; i < m.actions.length; i++)
          _actionCard(m, i),
      ],
    );
  }

  /// Asistan metnini [[urun:BARKOD|AD]] atiflarina gore parcalar:
  /// metin bloklari + FOTOGRAFLI tiklanabilir urun kartlari. Karta
  /// dokununca urun detay sayfasi (hub) acilir.
  Widget _richAssistantText(String text) {
    final re = RegExp(r'\[\[urun:([0-9A-Za-z]+)\|([^\]]+)\]\]');
    final children = <Widget>[];
    int last = 0;
    for (final m in re.allMatches(text)) {
      final before = text.substring(last, m.start).trim();
      if (before.isNotEmpty) children.add(_chatText(before));
      children.add(_ProductRefCard(
          barcode: m.group(1)!, name: m.group(2)!.trim()));
      last = m.end;
    }
    final tail = text.substring(last).trim();
    if (tail.isNotEmpty) children.add(_chatText(tail));
    if (children.isEmpty) children.add(_chatText(text));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          children[i],
        ],
      ],
    );
  }

  Widget _chatText(String t) => SelectableText(
        t,
        style: TextStyle(
            color: AppTheme.textPrimary, fontSize: 14.5, height: 1.3),
      );

  /// Tek bir eylem icin onay karti. Bekliyorken Onayla/İptal butonlari,
  /// islendikten sonra sonuc rozeti gosterir.
  Widget _actionCard(_ChatMsg m, int i) {
    final a = m.actions[i];
    final state = m.actionStates[i];
    final result = m.actionResults[i];
    final accent =
        a.isDestructive ? AppTheme.statusExpired : AppTheme.primary;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6, right: 40),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: accent.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  a.isDestructive
                      ? Icons.warning_amber_rounded
                      : Icons.bolt_rounded,
                  size: 17,
                  color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(a.title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: accent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Detay satirlari.
          ...a.details.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text('${d.label}:',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textTertiary)),
                    ),
                    Expanded(
                      child: Text(d.value,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 10),
          if (state == null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectAction(m, i),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('İptal'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: BorderSide(color: AppTheme.hairline),
                        padding:
                            const EdgeInsets.symmetric(vertical: 8)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _approveAction(m, i),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(a.isDestructive ? 'Sil, onayla' : 'Onayla'),
                    style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 8)),
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (state ? AppTheme.statusSafe : AppTheme.textTertiary)
                    .withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                result ?? (state ? 'İşleniyor…' : 'İptal edildi.'),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: state
                        ? AppTheme.statusSafe
                        : AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _typingBubble() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Dot(), _Dot(), _Dot(),
                  ],
                ),
              ),
              // AGENT: hangi araci kullandigini seffafca goster.
              if (_toolNote != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.build_rounded,
                    size: 13, color: AppTheme.textTertiary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(_toolNote!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppTheme.textTertiary)),
                ),
              ],
            ],
          ),
        ),
      );

  /// Dinlerken ustte gorunen canli serit: yanip sonen mikrofon + canli metin.
  Widget _listeningBar() {
    return Container(
      width: double.infinity,
      color: AppTheme.accent.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.mic_rounded, color: AppTheme.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _partial.isEmpty ? 'Dinliyorum… konuşun' : _partial,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _toggleListen,
            child: const Text('Durdur'),
          ),
        ],
      ),
    );
  }

  /// Barkod tara ve soruya ekle: kullanici bir urunun barkodunu okutup
  /// "bu nerede / bu ne / SKT'si var mi" diye sorabilsin. Taranan barkod
  /// giris kutusuna yazilir; kullanici ister sorusunu ekleyip gonderir,
  /// isterse direkt gonderir (asistan barkodu yerel veride arar).
  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final existing = _input.text.trim();
    setState(() {
      _input.text = existing.isEmpty
          ? 'Bu barkod hakkında bilgi ver: $code'
          : '$existing $code';
    });
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.hairline)),
          boxShadow: AppTheme.shadowMd,
        ),
        child: Row(
          children: [
            // ── BARKOD TARA: barkodu asistana gonder ──
            Material(
              color: AppTheme.primary.withOpacity(0.12),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _scanBarcode,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.qr_code_scanner_rounded,
                      color: AppTheme.primary),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // ── MIKROFON: sesli soru ──
            Material(
              color: _listening
                  ? AppTheme.statusExpired
                  : AppTheme.accent.withOpacity(0.15),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggleListen,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _listening ? Colors.white : AppTheme.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Ürün sor: pilavlık bulgur nerede?',
                  filled: true,
                  fillColor: AppTheme.surfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: _sending ? AppTheme.textTertiary : AppTheme.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sending
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        _send();
                      },
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: AppTheme.textTertiary,
          shape: BoxShape.circle,
        ),
      );
}


/// Asistan atifindan gelen FOTOGRAFLI urun karti — dokununca urun
/// detay sayfasi (hub) acilir. Foto: yerel dizin fotografi.
class _ProductRefCard extends StatelessWidget {
  final String barcode;
  final String name;
  const _ProductRefCard({required this.barcode, required this.name});

  Future<(String?, BarcodeEntry?)> _load() async {
    final repo = BarcodeDirectoryRepository(
        BarcodeDirectoryDataSource(DatabaseService.instance));
    String? photo;
    BarcodeEntry? entry;
    try {
      final p = await repo.getLocalImage(barcode);
      if (p != null && p.isNotEmpty && File(p).existsSync()) photo = p;
    } catch (_) {}
    try {
      entry = await repo.findEntryByBarcode(barcode);
    } catch (_) {}
    return (photo, entry);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(String?, BarcodeEntry?)>(
      future: _load(),
      builder: (context, snap) {
        final photo = snap.data?.$1;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final entry = snap.data?.$2 ??
                BarcodeEntry(
                  barcode: barcode,
                  productName: name,
                  importedAt: DateTime.now(),
                );
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BarcodeDetailScreen(entry: entry)));
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppTheme.primary.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: photo != null
                      ? Image.file(File(photo), fit: BoxFit.cover)
                      : const Icon(Icons.inventory_2_rounded,
                          size: 22, color: AppTheme.primary),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800)),
                      Text(barcode,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              color: AppTheme.textTertiary)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppTheme.primary),
              ],
            ),
          ),
        );
      },
    );
  }
}

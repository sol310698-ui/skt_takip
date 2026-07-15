import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/gemini_ocr_service.dart';
import '../../core/services/warehouse_assistant_service.dart';
import '../../core/theme/app_theme.dart';

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
  final String text;
  _ChatMsg(this.fromUser, this.text);
}

class _WarehouseChatScreenState extends State<WarehouseChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMsg> _messages = [];
  bool _sending = false;
  bool _hasKey = true;

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  @override
  void dispose() {
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
      final answer = await WarehouseAssistantService.instance
          .ask(history: history, question: q);
      if (!mounted) return;
      setState(() => _messages.add(_ChatMsg(false, answer.trim())));
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
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
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
      appBar: AppBar(
        title: const Text('Depo Asistanı'),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.accent),
      ),
      body: Column(
        children: [
          if (!_hasKey) _keyWarning(),
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

  Widget _keyWarning() => Container(
        width: double.infinity,
        color: AppTheme.statusWarning.withOpacity(0.15),
        padding: const EdgeInsets.all(10),
        child: Text(
          'Gemini API anahtarı ayarlı değil. Asistanı kullanmak için '
          'Ayarlar\'dan anahtarı girin.',
          style: TextStyle(color: AppTheme.statusWarning, fontSize: 12),
        ),
      );

  Widget _emptyState() {
    final examples = [
      'Pilavlık bulgur nerede?',
      'Ketçaplar hangi reyonda?',
      'Şehriyeli bulgur var mı, nerede?',
      'Salça hangi sütunda?',
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 20),
        Icon(Icons.assistant_rounded, size: 56, color: AppTheme.accent),
        const SizedBox(height: 12),
        const Text(
          'Depo Asistanı',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Ürünlerin yerini sor; önce telefondaki reyon kayıtlarından, '
          'yetmezse internetten yardımcı olurum.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
        ),
        const SizedBox(height: 22),
        ...examples.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: () {
                  _input.text = e;
                  _send();
                },
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  side: BorderSide(color: AppTheme.hairline),
                ),
                child: Text(e),
              ),
            )),
      ],
    );
  }

  Widget _bubble(_ChatMsg m) {
    final isUser = m.fromUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.accent : AppTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: AppTheme.hairline),
        ),
        child: SelectableText(
          m.text,
          style: TextStyle(
            color: isUser ? Colors.white : AppTheme.textPrimary,
            fontSize: 14.5,
            height: 1.3,
          ),
        ),
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
          child: const SizedBox(
            width: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Dot(), _Dot(), _Dot(),
              ],
            ),
          ),
        ),
      );

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.hairline)),
        ),
        child: Row(
          children: [
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

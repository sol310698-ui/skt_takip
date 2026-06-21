import 'package:flutter/material.dart';

import '../../core/services/assistant_service.dart';
import '../../core/services/gemini_ocr_service.dart';
import '../../core/services/voice_service.dart';
import '../../core/theme/app_theme.dart';

/// Asistan "Pia" sohbet ekrani — yazili + sesli.
class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({super.key});

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _listening = false;
  bool _voiceReply = true; // asistan cevaplarini sesli oku

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    VoiceService.instance.stopSpeaking();
    VoiceService.instance.stopListening();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    _scrollToBottom();
    try {
      final reply = await AssistantService.instance.send(text);
      if (!mounted) return;
      setState(() => _sending = false);
      _scrollToBottom();
      if (_voiceReply) VoiceService.instance.speak(reply);
    } on GeminiOcrException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await VoiceService.instance.stopListening();
      setState(() => _listening = false);
      return;
    }
    // Asistan konusuyorsa once sustur.
    await VoiceService.instance.stopSpeaking();
    final ok = await VoiceService.instance.listen(
      onResult: (text, isFinal) {
        setState(() => _input.text = text);
        if (isFinal) {
          setState(() => _listening = false);
          if (text.trim().isNotEmpty) _send(text);
        }
      },
    );
    if (ok) {
      setState(() => _listening = true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Mikrofon kullanılamıyor (izin verildi mi?)'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = AssistantService.instance.history;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: AppTheme.accentGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Pia', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _voiceReply ? 'Sesli yanıt açık' : 'Sesli yanıt kapalı',
            icon: Icon(_voiceReply
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded),
            onPressed: () => setState(() => _voiceReply = !_voiceReply),
          ),
          IconButton(
            tooltip: 'Sohbeti temizle',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () {
              AssistantService.instance.clear();
              VoiceService.instance.stopSpeaking();
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgs.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: msgs.length + (_sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= msgs.length) return _typingBubble();
                      return _bubble(msgs[i]);
                    },
                  ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppTheme.accentGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            Text('Merhaba, ben Pia 👋',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'SKT, raf, fiyat, mağaza işleri… sor, yardımcı olayım. '
              'Yazabilir veya mikrofona basıp konuşabilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser
              ? null
              : Border.all(color: AppTheme.hairline, width: 1),
        ),
        child: Text(
          m.text,
          style: TextStyle(
            color: isUser ? Colors.white : AppTheme.textPrimary,
            fontSize: 15,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.hairline, width: 1),
        ),
        child: const SizedBox(
          width: 36,
          height: 8,
          child: _TypingDots(),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.hairline)),
      ),
      child: Row(
        children: [
          // Mikrofon
          GestureDetector(
            onTap: _toggleMic,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _listening
                    ? AppTheme.statusExpired
                    : AppTheme.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _listening ? Icons.stop_rounded : Icons.mic_rounded,
                color: _listening ? Colors.white : AppTheme.textSecondary,
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
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: _listening ? 'Dinliyorum…' : 'Mesaj yaz…',
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : () => _send(),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _sending ? AppTheme.surfaceHigh : AppTheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_c.value + i * 0.2) % 1.0;
            final o = (t < 0.5) ? 0.3 + t : 0.3 + (1 - t);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(o.clamp(0.3, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

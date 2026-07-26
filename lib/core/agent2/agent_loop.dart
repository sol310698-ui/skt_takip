import 'agent_core.dart';
import 'agent_llm.dart';

/// Ajanın karar döngüsü: düşün → çağır → değerlendir.
///  1. LLM çağrılır (system prompt + geçmiş + araç tanımları).
///  2. Araç çağırdıysa → araçlar çalışır, sonuçlar geçmişe eklenir → 1'e dön.
///  3. Düz metin döndürürse → nihai cevap, döngü biter.
class AgentLoop {
  final AgentLlm llm;
  final Map<String, AgentTool> tools;
  final String systemPrompt;
  final int maxSteps;

  AgentLoop({
    required this.llm,
    required this.tools,
    required this.systemPrompt,
    this.maxSteps = 12,
  });

  List<Map<String, dynamic>> get _declarations =>
      tools.values.map((t) => t.toDeclaration()).toList();

  /// Döngüyü çalıştırır; her mesajda [onEvent], araç çalışırken [onStep].
  /// Nihai asistan metnini döndürür.
  Future<String> run(
    List<AgentMsg> history, {
    void Function(AgentMsg msg)? onEvent,
    void Function(String note)? onStep,
  }) async {
    for (var step = 0; step < maxSteps; step++) {
      final reply = await llm.send(
        history: history,
        systemPrompt: systemPrompt,
        toolDeclarations: _declarations,
      );
      history.add(reply);
      onEvent?.call(reply);

      if (!reply.hasToolCalls) return reply.text;

      onStep?.call(reply.toolCalls.map((c) => c.name).join(', '));

      for (final call in reply.toolCalls) {
        final result = await _execute(call);
        final toolMsg = AgentMsg(role: AgentRole.tool, toolResult: result);
        history.add(toolMsg);
        onEvent?.call(toolMsg);
      }
    }
    return 'İşlem adım sınırına ($maxSteps) ulaştı; biraz daha açık yazar mısın?';
  }

  Future<AgentToolResult> _execute(AgentToolCall call) async {
    final tool = tools[call.name];
    if (tool == null) {
      return AgentToolResult(
        callId: call.id,
        name: call.name,
        ok: false,
        output: 'Bilinmeyen araç: ${call.name}',
      );
    }
    try {
      final out = await tool.run(call.args);
      return AgentToolResult(
          callId: call.id, name: call.name, ok: true, output: out);
    } catch (e) {
      return AgentToolResult(
          callId: call.id, name: call.name, ok: false, output: 'Araç hatası: $e');
    }
  }
}

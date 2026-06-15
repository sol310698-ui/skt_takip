import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/services/alarm_service.dart';
import '../../core/theme/app_theme.dart';
import 'shift_screen.dart';

/// Alarm caldiginda acilan tam ekran modern ekran.
/// Saat, tarih, kayan "Kaydir ve kapat" butonu, ertele.
class AlarmRingScreen extends StatefulWidget {
  final int alarmId;
  final String title;
  final String body;
  final bool isShift;
  final int? shiftId;

  const AlarmRingScreen({
    super.key,
    required this.alarmId,
    required this.title,
    required this.body,
    this.isShift = false,
    this.shiftId,
  });

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _ringRotate;
  Timer? _clock;
  DateTime _now = DateTime.now();
  double _slideValue = 0.0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _ringRotate = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _ringRotate.dispose();
    _clock?.cancel();
    super.dispose();
  }

  /// Alarm ekranini kapat. Uygulamayi acmak yerine arka plana atar.
  void _closeAlarm() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    SystemNavigator.pop();
  }

  Future<void> _dismiss() async {
    await AlarmService.stop(widget.alarmId);
    _closeAlarm();
  }

  /// 5 dakika ertele: alarmi durdur, yeni alarmi 5 dk sonraya kur.
  Future<void> _snooze() async {
    await AlarmService.stop(widget.alarmId);
    await AlarmService.setAlarmAt(
      id: widget.alarmId,
      when: DateTime.now().add(const Duration(minutes: 5)),
      title: widget.title,
      body: widget.body,
    );
    _closeAlarm();
  }

  Future<void> _shiftFinish() async {
    await AlarmService.stop(widget.alarmId);
    if (!mounted) return;
    // Cikis ekranina yonlendir (uygulamada kal).
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShiftScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isShift = widget.isShift;
    final accent = isShift ? AppTheme.coral : AppTheme.primary;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withOpacity(0.35),
                AppTheme.background,
                AppTheme.background,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Saat
                Text(
                  DateFormat('HH:mm').format(_now),
                  style: const TextStyle(
                    fontSize: 76,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 2,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('d MMMM EEEE', 'tr').format(_now),
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const Spacer(),

                // Pulse halka + ikon
                AnimatedBuilder(
                  animation: Listenable.merge([_pulse, _ringRotate]),
                  builder: (_, __) {
                    return SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Dış pulse halkalar
                          ...List.generate(3, (i) {
                            final t =
                                (_pulse.value + i * 0.33).clamp(0.0, 1.0);
                            return Container(
                              width: 120 + t * 80,
                              height: 120 + t * 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accent.withOpacity((1 - t) * 0.4),
                                  width: 2,
                                ),
                              ),
                            );
                          }),
                          // Dönen kesikli halka
                          Transform.rotate(
                            angle: _ringRotate.value * 2 * math.pi,
                            child: CustomPaint(
                              size: const Size(140, 140),
                              painter: _DashedRingPainter(accent),
                            ),
                          ),
                          // Merkez ikon
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [accent, accent.withOpacity(0.6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.5),
                                  blurRadius: 30,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Icon(
                              isShift
                                  ? Icons.logout_rounded
                                  : Icons.alarm_rounded,
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Başlık
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      widget.body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary),
                    ),
                  ),
                ],

                const Spacer(flex: 2),

                // Aksiyonlar
                if (isShift)
                  _shiftActions(accent)
                else
                  _slideToDismiss(accent),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Mesai çıkış: iki buton.
  Widget _shiftActions(Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _shiftFinish,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Çıkış Yap',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _snooze,
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Ertele (5 dk)'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: _dismiss,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Yoksay',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Normal alarm: kaydırarak kapat + ertele.
  Widget _slideToDismiss(Color accent) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth - 64;
              return Container(
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                      color: accent.withOpacity(0.3), width: 1),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'Kaydır ve kapat',
                      style: TextStyle(
                        color: AppTheme.textTertiary
                            .withOpacity(1 - _slideValue),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (d) {
                          setState(() {
                            _slideValue =
                                (_slideValue + d.delta.dx / maxW)
                                    .clamp(0.0, 1.0);
                          });
                        },
                        onHorizontalDragEnd: (_) {
                          if (_slideValue > 0.7) {
                            _dismiss();
                          } else {
                            setState(() => _slideValue = 0);
                          }
                        },
                        child: Transform.translate(
                          offset: Offset(_slideValue * maxW, 0),
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent,
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.5),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.chevron_right_rounded,
                                color: Colors.white, size: 30),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: _snooze,
          icon: const Icon(Icons.snooze_rounded, size: 20),
          label: const Text('Ertele (5 dakika)'),
          style: TextButton.styleFrom(foregroundColor: accent),
        ),
      ],
    );
  }
}

/// Dönen kesikli halka çizimi.
class _DashedRingPainter extends CustomPainter {
  final Color color;
  _DashedRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const dashes = 24;
    const gap = 0.5;
    final sweep = (2 * math.pi / dashes) * (1 - gap);
    for (int i = 0; i < dashes; i++) {
      final start = (2 * math.pi / dashes) * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

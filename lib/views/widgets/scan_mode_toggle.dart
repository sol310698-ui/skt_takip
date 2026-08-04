import 'package:flutter/material.dart';

/// ════════════════════════════════════════════════════════════════════
///  TARAMA MODU SWITCH'i (her tarayici ekraninda gorunur)
/// ────────────────────────────────────────────────────────────────────
///  value = true  -> EAN-13 KESIN (kontrol basamagi dogrulanir)
///  value = false -> HEPSI (Code128 dahil her format)
///  QR'dan barkod cikarma her iki modda da aciktir.
///
///  Kamera uzerinde de okunakli olsun diye kendi zeminini (yari-saydam)
///  tasir; dokununca modu degistirir.
/// ════════════════════════════════════════════════════════════════════
class ScanModeToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const ScanModeToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // EAN-13 kesin: yesil; Hepsi: turuncu.
    final Color c = value ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);
    return Material(
      color: Colors.black.withOpacity(0.45),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.verified_rounded : Icons.all_inclusive_rounded,
                size: 16,
                color: c,
              ),
              const SizedBox(width: 6),
              Text(
                value ? 'EAN-13 · kesin' : 'Hepsi · Code128/QR',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              // Mini switch gostergesi.
              Container(
                width: 34,
                height: 18,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

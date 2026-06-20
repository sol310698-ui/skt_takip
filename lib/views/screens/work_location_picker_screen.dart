import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/app_lock_service.dart';
import '../../core/theme/app_theme.dart';

/// İş yeri konumunu haritadan işaretleyerek belirleme ekranı.
/// Harita ortasındaki sabit pin'i sürükleyerek/haritayı kaydırarak konum
/// seçilir; "Burayı İş Yeri Olarak Kaydet" ile onaylanır.
class WorkLocationPickerScreen extends StatefulWidget {
  const WorkLocationPickerScreen({super.key});

  @override
  State<WorkLocationPickerScreen> createState() =>
      _WorkLocationPickerScreenState();
}

class _WorkLocationPickerScreenState extends State<WorkLocationPickerScreen> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(41.0082, 28.9784); // İstanbul varsayılan
  double _radiusMeters = 150;
  bool _loadingLocation = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    // Onceden kayitli is yeri varsa onu goster.
    final existing = await AppLockService.instance.getWorkLocation();
    if (existing != null) {
      setState(() {
        _center = LatLng(existing.lat, existing.lng);
        _radiusMeters = existing.radius;
        _loadingLocation = false;
      });
      return;
    }
    // Yoksa kullanicinin su anki konumunu baslangic noktasi yap (varsa).
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (mounted) {
        setState(() {
          _center = LatLng(pos.latitude, pos.longitude);
          _loadingLocation = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await AppLockService.instance.setWorkLocation(
      _center.latitude,
      _center.longitude,
      radiusMeters: _radiusMeters,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('İş yeri konumunu kaldır'),
        content: const Text(
            'Kayıtlı iş yeri konumu silinecek, otomatik tespit artık çalışmayacak. Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.statusExpired),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppLockService.instance.clearWorkLocation();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('İş Yeri Konumu'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
        actions: [
          TextButton(
            onPressed: _clear,
            child: const Text('Kaldır',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: _loadingLocation
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'Haritayı kaydırarak iş yerinizi ortadaki pine getirin.',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: 16,
                          onPositionChanged: (pos, hasGesture) {
                            if (hasGesture && pos.center != null) {
                              setState(() => _center = pos.center!);
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.skt_takip',
                          ),
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: _center,
                                radius: _radiusMeters,
                                useRadiusInMeter: true,
                                color: AppTheme.primary.withOpacity(0.15),
                                borderColor: AppTheme.primary,
                                borderStrokeWidth: 2,
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Sabit ortadaki pin (harita kaydırılır, pin sabit kalır).
                      const Icon(Icons.location_pin,
                          size: 48, color: AppTheme.statusExpired),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration: const BoxDecoration(color: AppTheme.surface),
                  child: Row(
                    children: [
                      const Text('Yarıçap:',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: _radiusMeters,
                          min: 50,
                          max: 500,
                          divisions: 9,
                          activeColor: AppTheme.accent,
                          label: '${_radiusMeters.round()} m',
                          onChanged: (v) =>
                              setState(() => _radiusMeters = v),
                        ),
                      ),
                      Text('${_radiusMeters.round()} m',
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded),
                      label: const Text('Burayı İş Yeri Olarak Kaydet',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

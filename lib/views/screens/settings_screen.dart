import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/theme_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Modern settings screen with clean sections and toggles.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedBuilder(
      animation: ThemePrefs.instance,
      builder: (context, _) {
        final isDark = ThemePrefs.instance.mode == ThemeMode.dark;
        return Scaffold(
          backgroundColor: AppTheme.scaffold,
          appBar: AppBar(
            title: const Text('Ayarlar'),
            backgroundColor: AppTheme.scaffold,
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SectionHeader(title: 'Görünüm'),
              _SettingsTile(
                title: 'Koyu Tema',
                subtitle: 'Gece kullanımı için koyu arayüz',
                icon: Icons.dark_mode_outlined,
                onTap: () async {
                  await ThemePrefs.instance.setMode(isDark ? ThemeMode.light : ThemeMode.dark);
                  AppTheme.applyBrightness(ThemePrefs.instance.mode == ThemeMode.light);
                },
                trailing: Switch(
                  value: isDark,
                  onChanged: (value) async {
                    await ThemePrefs.instance.setMode(value ? ThemeMode.dark : ThemeMode.light);
                    AppTheme.applyBrightness(ThemePrefs.instance.mode == ThemeMode.light);
                  },
                ),
              ),
              _SettingsTile(
                title: 'Kompakt Görünüm',
                subtitle: 'Daha az boşluklu liste görünümü',
                icon: Icons.density_medium_outlined,
                onTap: () {},
                trailing: Switch(value: true, onChanged: (_) {}),
              ),
              const SizedBox(height: 16),
              SectionHeader(title: 'Bildirimler'),
              _SettingsTile(
                title: 'Süresi Yaklaşan Ürünler',
                subtitle: 'SKT 7 gün kaldığında bildir',
                icon: Icons.notifications_outlined,
                onTap: () {},
                trailing: Switch(value: true, onChanged: (_) {}),
              ),
              _SettingsTile(
                title: 'Süresi Dolmuş Ürünler',
                subtitle: 'SKT geçmiş ürünler için uyarı',
                icon: Icons.warning_outlined,
                onTap: () {},
                trailing: Switch(value: true, onChanged: (_) {}),
              ),
              const SizedBox(height: 16),
              SectionHeader(title: 'Veri'),
              _SettingsTile(
                title: 'Verileri Senkronize Et',
                subtitle: 'Son 2 dakika önce senkronize edildi',
                icon: Icons.sync_outlined,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Senkronizasyon yakında eklenecek.')),
                  );
                },
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
              ),
              _SettingsTile(
                title: 'Yedekle',
                subtitle: 'Verileri buluta yedekle',
                icon: Icons.cloud_upload_outlined,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Yedekleme yakında eklenecek.')),
                  );
                },
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
              ),
              _SettingsTile(
                title: 'Geri Yükle',
                subtitle: 'Yedekten veri geri yükle',
                icon: Icons.cloud_download_outlined,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Geri yükleme yakında eklenecek.')),
                  );
                },
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              SectionHeader(title: 'Hakkında'),
              _SettingsTile(
                title: 'Sürüm',
                subtitle: 'v1.2.0',
                icon: Icons.info_outlined,
                onTap: () {},
                trailing: const SizedBox(),
              ),
              _SettingsTile(
                title: 'Gizlilik Politikası',
                subtitle: 'Verileriniz nasıl kullanıldığını öğrenin',
                icon: Icons.privacy_tip_outlined,
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Gizlilik Politikası'),
                      content: const Text(
                        'Bu uygulama ürün verilerini cihazınızda saklar. Ekstra veri paylaşımı yapılmaz.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Kapat'),
                        ),
                      ],
                    ),
                  );
                },
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
              ),
              _SettingsTile(
                title: 'Kullanım Şartları',
                subtitle: 'SKT Takip kullanım kuralları',
                icon: Icons.description_outlined,
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Kullanım Şartları'),
                      content: const Text(
                        'Uygulama, işaretli ürün kayıtları ve operasyonel takip için tasarlanmıştır. Yetkisiz kullanım izin verilmez.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Kapat'),
                        ),
                      ],
                    ),
                  );
                },
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Çıkış işlemi yakında eklenecek.')),
                    );
                  },
                  child: const Text('Çıkış Yap'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

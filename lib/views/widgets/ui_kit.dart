import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared UI building blocks used across app screens.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = iconColor ?? AppTheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [c.withOpacity(0.18), c.withOpacity(0.06)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(icon, size: 44, color: c),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Backward-compatible alias used by older screens.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message = 'Yükleniyor...'});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(message),
        ]),
      );
}

/// Backward-compatible error state with an optional retry action.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.error_outline,
        iconColor: AppTheme.danger,
        title: 'Bir hata oluştu',
        subtitle: error.toString(),
        action: onRetry == null
            ? null
            : OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar dene'),
              ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(child: Text(title,
              style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Older name retained so existing screens keep compiling.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SectionHeader(
        title: label,
        trailing: trailing,
      );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child,
      this.padding = const EdgeInsets.all(16), this.margin, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: child,
      );
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child,
      this.padding = const EdgeInsets.all(16), this.margin});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.76),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border.withOpacity(0.7)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: child,
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
      );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value,
      required this.color, this.onTap});
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: color)),
              const SizedBox(height: 3),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}

class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, this.onPressed,
      this.icon, this.isPrimary = true});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isPrimary ? AppTheme.primary : AppTheme.surface,
          foregroundColor: isPrimary ? AppTheme.white : AppTheme.text,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: isPrimary ? Colors.transparent : AppTheme.border)),
        ),
        icon: icon == null ? const SizedBox.shrink() : Icon(icon),
        label: Text(label),
      );
}

// Image helpers intentionally remain small and dependency-free. Existing
// screens can use them without losing the old UI-kit API.
class CachedImage extends StatelessWidget {
  const CachedImage({super.key, required this.url, this.width, this.height,
      this.fit = BoxFit.cover});
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.network(url, width: width,
      height: height, fit: fit, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported));
}

class SmartProductImage extends StatelessWidget {
  const SmartProductImage({super.key, this.url, this.size = 56});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: url == null || url!.isEmpty
            ? Icon(Icons.inventory_2_outlined, size: size * .55,
                color: AppTheme.primary)
            : CachedImage(url: url!, width: size, height: size),
      );
}

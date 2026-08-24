import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system tokens for the Zwesta trading app.
/// Use these consistently across all screens for a professional look.
class AppDesign {
  // ─── Border Radius ───
  static const double radiusXs = 6;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radius2Xl = 24;
  static const double radiusFull = 999;

  // ─── Spacing ───
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;
  static const double space48 = 48;

  // ─── Opacity ───
  static const double opacityHover = 0.08;
  static const double opacityPressed = 0.12;
  static const double opacityDisabled = 0.38;
  static const double opacitySubtle = 0.04;
  static const double opacityBorder = 0.12;
  static const double opacityBorderStrong = 0.24;
  static const double opacityOverlay = 0.60;
  static const double opacityMuted = 0.54;
  static const double opacityFaint = 0.30;

  // ─── Elevation ───
  static const double elevationNone = 0;
  static const double elevationLow = 2;
  static const double elevationMd = 4;
  static const double elevationLg = 8;
  static const double elevationXl = 16;

  // ─── Animation ───
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 400);
  static const Curve animCurve = Curves.easeOutCubic;

  // ─── Icon Sizes ───
  static const double iconXs = 14;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;
  static const double icon2Xl = 48;
  static const double icon3Xl = 64;
}

/// Semantic color accessor — use context.colors.profit, context.colors.loss, etc.
extension AppColors on BuildContext {
  Color get profit => Theme.of(this).extension<AppSemanticColors>()?.profit ?? const Color(0xFF4CAF50);
  Color get loss => Theme.of(this).extension<AppSemanticColors>()?.loss ?? const Color(0xFFFF5252);
  Color get success => Theme.of(this).extension<AppSemanticColors>()?.success ?? const Color(0xFF4CAF50);
  Color get danger => Theme.of(this).extension<AppSemanticColors>()?.danger ?? const Color(0xFFFF5252);
  Color get warning => Theme.of(this).extension<AppSemanticColors>()?.warning ?? const Color(0xFFFFB74D);
  Color get info => Theme.of(this).extension<AppSemanticColors>()?.info ?? const Color(0xFF64B5F6);
  Color get neutral => Theme.of(this).extension<AppSemanticColors>()?.neutral ?? const Color(0xFFB0BEC5);

  Color get primary => Theme.of(this).colorScheme.primary;
  Color get surface => Theme.of(this).colorScheme.surface;
  Color get background => Theme.of(this).scaffoldBackgroundColor;
  Color get onSurface => Theme.of(this).colorScheme.onSurface;

  Color get cardBg => Theme.of(this).cardTheme.color ?? surface;
  Color get border => Colors.white.withOpacity(AppDesign.opacityBorder);
  Color get borderStrong => Colors.white.withOpacity(AppDesign.opacityBorderStrong);
  Color get muted => onSurface.withOpacity(AppDesign.opacityMuted);
  Color get subtle => onSurface.withOpacity(AppDesign.opacityFaint);
}

/// Consistent text styles
extension AppTextStyles on BuildContext {
  TextStyle get heading => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: onSurface,
      );

  TextStyle get title => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
      );

  TextStyle get subtitle => GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: muted,
      );

  TextStyle get body => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: onSurface,
      );

  TextStyle get bodySm => GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: muted,
      );

  TextStyle get caption => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: subtle,
        letterSpacing: 0.3,
      );

  TextStyle get label => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: muted,
        letterSpacing: 0.5,
      );

  TextStyle get metric => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
      );

  TextStyle get metricSm => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
      );

  TextStyle profitText(double value) => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: value >= 0 ? profit : loss,
      );
}

/// Reusable card widget with consistent styling
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? radius;
  final double? elevation;
  final Border? border;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadows;

  const AppAppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.radius,
    this.elevation,
    this.border,
    this.onTap,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final cardRadius = radius ?? AppDesign.radiusLg;
    final cardColor = color ?? context.cardBg;

    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(cardRadius),
        border: border ?? Border.all(color: context.border),
        boxShadow: shadows ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: elevation?.toDouble() ?? 8,
                offset: const Offset(0, 2),
              ),
            ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(cardRadius),
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(cardRadius),
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(AppDesign.space16),
                  child: child,
                ),
              )
            : Padding(
                padding: padding ?? const EdgeInsets.all(AppDesign.space16),
                child: child,
              ),
      ),
    );
  }
}

/// Glass-morphism card for dashboard
class AppGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  const AppGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(AppDesign.opacitySubtle + 0.02),
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        border: Border.all(color: context.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppDesign.radiusMd),
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(AppDesign.space16),
                  child: child,
                ),
              )
            : Padding(
                padding: padding ?? const EdgeInsets.all(AppDesign.space16),
                child: child,
              ),
      ),
    );
  }
}

/// Consistent button styles
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expanded;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;

    Color bgColor;
    Color fgColor;
    Color? borderColor;

    switch (variant) {
      case AppButtonVariant.primary:
        bgColor = context.primary;
        fgColor = Colors.white;
        break;
      case AppButtonVariant.secondary:
        bgColor = Colors.transparent;
        fgColor = context.onSurface;
        borderColor = context.borderStrong;
        break;
      case AppButtonVariant.danger:
        bgColor = context.danger;
        fgColor = Colors.white;
        break;
      case AppButtonVariant.success:
        bgColor = context.success;
        fgColor = Colors.white;
        break;
      case AppButtonVariant.ghost:
        bgColor = Colors.transparent;
        fgColor = context.onSurface;
        break;
    }

    final verticalPad = size == AppButtonSize.sm ? AppDesign.space8 : AppDesign.space12;
    final horizontalPad = size == AppButtonSize.sm ? AppDesign.space16 : AppDesign.space24;
    final fontSize = size == AppButtonSize.sm ? 13.0 : 14.0;

    Widget content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: AppDesign.iconSm,
            height: AppDesign.iconSm,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(fgColor),
            ),
          )
        else if (icon != null) ...[
          Icon(icon, size: AppDesign.iconSm),
          const SizedBox(width: AppDesign.space8),
        ],
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: fgColor,
          ),
        ),
      ],
    );

    final button = variant == AppButtonVariant.secondary
        ? OutlinedButton(
            onPressed: isDisabled ? null : onPressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: fgColor,
              side: BorderSide(color: borderColor ?? context.border),
              padding: EdgeInsets.symmetric(vertical: verticalPad, horizontal: horizontalPad),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDesign.radiusMd),
              ),
            ),
            child: content,
          )
        : ElevatedButton(
            onPressed: isDisabled ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: fgColor,
              disabledBackgroundColor: bgColor.withOpacity(0.4),
              disabledForegroundColor: fgColor.withOpacity(0.6),
              elevation: variant == AppButtonVariant.ghost ? 0 : 2,
              padding: EdgeInsets.symmetric(vertical: verticalPad, horizontal: horizontalPad),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDesign.radiusMd),
              ),
            ),
            child: content,
          );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

enum AppButtonVariant { primary, secondary, danger, success, ghost }
enum AppButtonSize { sm, md }

/// Consistent empty state widget
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppDesign.icon3Xl,
              color: context.subtle,
            ),
            const SizedBox(height: AppDesign.space16),
            Text(
              title,
              style: context.title,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppDesign.space8),
              Text(
                subtitle!,
                style: context.bodySm,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppDesign.space24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Consistent metric card for dashboards
class AppMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final String? subtitle;

  const AppMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppDesign.iconSm, color: context.muted),
                const SizedBox(width: AppDesign.space8),
              ],
              Expanded(
                child: Text(label, style: context.caption, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: AppDesign.space8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: valueColor ?? context.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppDesign.space4),
            Text(subtitle!, style: context.caption),
          ],
        ],
      ),
    );
  }
}

/// Skeleton loading placeholder
class AppSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const AppSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = AppDesign.radiusSm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.border,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Consistent chip/badge widget
class AppBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final bool outlined;

  const AppBadge({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = (color ?? context.primary).withOpacity(outlined ? 0.1 : 0.15);
    final fgColor = color ?? context.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppDesign.space10, vertical: AppDesign.space4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusFull),
        border: outlined ? Border.all(color: fgColor.withOpacity(0.3)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppDesign.iconXs, color: fgColor),
            const SizedBox(width: AppDesign.space4),
          ],
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Consistent section header
class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDesign.space16, vertical: AppDesign.space12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: context.label,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Consistent divider
class AppDivider extends StatelessWidget {
  const AppDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: context.border,
    );
  }
}

/// Consistent spacing widget
class AppGap extends StatelessWidget {
  final double? width;
  final double? height;

  const AppGap({super.key, this.width, this.height});
  const AppGap.sm({super.key}) : width = AppDesign.space8, height = AppDesign.space8;
  const AppGap.md({super.key}) : width = AppDesign.space16, height = AppDesign.space16;
  const AppGap.lg({super.key}) : width = AppDesign.space24, height = AppDesign.space24;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height);
  }
}

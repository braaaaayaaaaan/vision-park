import 'package:flutter/material.dart';

import '../app/app_config.dart';
import '../app/app_theme.dart';
import 'brand_falcon.g.dart';

class VisionParkFalcon extends StatelessWidget {
  const VisionParkFalcon({
    this.width = 44,
    this.color = AppTheme.blue,
    super.key,
  });

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * falconViewBox.height / falconViewBox.width,
    child: CustomPaint(painter: _FalconPainter(color)),
  );
}

class _FalconPainter extends CustomPainter {
  const _FalconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / falconViewBox.width,
      size.height / falconViewBox.height,
    );
    canvas.translate(-falconViewBox.left, -falconViewBox.top);
    canvas.drawPath(falconPath, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FalconPainter oldDelegate) => color != oldDelegate.color;
}

/// Keep room for the back button, actions, and enlarged accessibility text.
class VisionParkBrand extends StatelessWidget {
  const VisionParkBrand({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textSize = MediaQuery.textScalerOf(context).scale(20);
      final showFalcon = constraints.maxWidth >= textSize * 5.6 + 56;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showFalcon) ...[
            const VisionParkFalcon(color: AppTheme.white),
            const SizedBox(width: 10),
          ],
          const Flexible(
            child: Text(
              AppConfig.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    },
  );
}

class BrandIconBadge extends StatelessWidget {
  const BrandIconBadge(this.icon, {this.size = 38, super.key});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: AppTheme.blueSoft,
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: size * .52, color: AppTheme.blue),
  );
}

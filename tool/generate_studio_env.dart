/// Generates studio-style equirectangular environment maps for PBR rendering.
///
/// Produces two PNGs:
///   - studio_radiance.png  : sharp highlights (specular reflections)
///   - studio_irradiance.png: soft diffuse fill (blurred/averaged version)
///
/// Run with: dart run tool/generate_studio_env.dart
library;

import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  const radW = 512;
  const radH = 256;
  const irrW = 64;
  const irrH = 32;
  const baseAmbient = 12;

  // ---------------------------------------------------------------------------
  // 1. Radiance map — mostly black with two soft white area-light ellipses
  //    positioned like studio softboxes: one top-front, one subtle bottom fill.
  // ---------------------------------------------------------------------------
  final radiance = img.Image(width: radW, height: radH, numChannels: 4);

  // Fill with a neutral high-key gradient so metallic badges keep color.
  for (int y = 0; y < radH; y++) {
    for (int x = 0; x < radW; x++) {
      final t = y / (radH - 1);
      final topLift = (1.0 - t);
      final bottomLift = t;

      final r = (baseAmbient + topLift * 10 + bottomLift * 2).round().clamp(
        0,
        255,
      );
      final g = (baseAmbient + topLift * 11 + bottomLift * 3).round().clamp(
        0,
        255,
      );
      final b = (baseAmbient + topLift * 14 + bottomLift * 4).round().clamp(
        0,
        255,
      );

      radiance.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Broad front card keeps front-facing badges vibrant.
  _drawSoftLight(
    radiance,
    centerU: 0.50,
    centerV: 0.46,
    radiusU: 0.30,
    radiusV: 0.22,
    intensity: 95,
    warmth: 0.01,
  );

  // Key light: top-center softbox.
  _drawSoftLight(
    radiance,
    centerU: 0.50,
    centerV: 0.28,
    radiusU: 0.18,
    radiusV: 0.14,
    intensity: 210,
    warmth: 0.03,
  );

  // Fill light: lower front, slightly warm bounce.
  _drawSoftLight(
    radiance,
    centerU: 0.50,
    centerV: 0.80,
    radiusU: 0.28,
    radiusV: 0.11,
    intensity: 120,
    warmth: 0.02,
  );

  // Right side kicker.
  _drawSoftLight(
    radiance,
    centerU: 0.74,
    centerV: 0.36,
    radiusU: 0.12,
    radiusV: 0.15,
    intensity: 150,
    warmth: 0.0,
  );

  // Left side kicker.
  _drawSoftLight(
    radiance,
    centerU: 0.26,
    centerV: 0.40,
    radiusU: 0.11,
    radiusV: 0.14,
    intensity: 135,
    warmth: -0.02,
  );

  // Top rim accent helps edge highlights during flips.
  _drawSoftLight(
    radiance,
    centerU: 0.52,
    centerV: 0.08,
    radiusU: 0.14,
    radiusV: 0.08,
    intensity: 120,
    warmth: -0.01,
  );

  final radiancePng = img.encodePng(radiance);
  File('assets/env/studio_radiance.png').writeAsBytesSync(radiancePng);
  print('✓ assets/env/studio_radiance.png (${radW}x$radH)');

  // ---------------------------------------------------------------------------
  // 2. Irradiance map — heavily blurred / averaged version for diffuse lighting.
  //    We generate at low res and apply a large Gaussian blur.
  // ---------------------------------------------------------------------------
  final irradiance = img.Image(width: irrW, height: irrH, numChannels: 4);

  // Sample down the radiance map into the small irradiance image
  for (int y = 0; y < irrH; y++) {
    for (int x = 0; x < irrW; x++) {
      // Box-sample from radiance
      final srcX = (x / irrW * radW).floor().clamp(0, radW - 1);
      final srcY = (y / irrH * radH).floor().clamp(0, radH - 1);
      final p = radiance.getPixel(srcX, srcY);
      irradiance.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
    }
  }

  // Heavy Gaussian blur to simulate cosine-weighted hemisphere convolution
  final blurred = img.gaussianBlur(irradiance, radius: 12);

  // Brighter diffuse floor keeps material albedo visible under ACES tonemapping.
  for (int y = 0; y < irrH; y++) {
    for (int x = 0; x < irrW; x++) {
      final p = blurred.getPixel(x, y);
      const scale = 1.05;
      const diffuseFloor = 18;
      blurred.setPixelRgba(
        x,
        y,
        ((p.r * scale).round()).clamp(diffuseFloor, 255),
        ((p.g * scale).round()).clamp(diffuseFloor, 255),
        ((p.b * scale).round()).clamp(diffuseFloor, 255),
        255,
      );
    }
  }

  final irradiancePng = img.encodePng(blurred);
  File('assets/env/studio_irradiance.png').writeAsBytesSync(irradiancePng);
  print('✓ assets/env/studio_irradiance.png (${irrW}x$irrH)');

  print('\nDone! Add these to your Flutter assets and load with:');
  print('  EnvironmentMap.fromAssets(');
  print("    radiance: 'assets/env/studio_radiance.png',");
  print("    irradiance: 'assets/env/studio_irradiance.png',");
  print('  )');
}

/// Draws a soft elliptical light on an equirectangular map.
///
/// [centerU], [centerV] are in 0..1 UV space.
/// [radiusU], [radiusV] define the ellipse half-extents in UV space.
/// [intensity] is peak brightness (0-255).
/// [warmth] shifts R up and B down for warm tint (negative = cool).
void _drawSoftLight(
  img.Image image, {
  required double centerU,
  required double centerV,
  required double radiusU,
  required double radiusV,
  required int intensity,
  double warmth = 0.0,
}) {
  final w = image.width;
  final h = image.height;

  // Expand search region generously
  final x0 = ((centerU - radiusU * 2) * w).floor().clamp(0, w - 1);
  final x1 = ((centerU + radiusU * 2) * w).ceil().clamp(0, w - 1);
  final y0 = ((centerV - radiusV * 2) * h).floor().clamp(0, h - 1);
  final y1 = ((centerV + radiusV * 2) * h).ceil().clamp(0, h - 1);

  for (int y = y0; y <= y1; y++) {
    for (int x = x0; x <= x1; x++) {
      final u = x / w;
      final v = y / h;

      // Normalized distance from center of the ellipse
      final du = (u - centerU) / radiusU;
      final dv = (v - centerV) / radiusV;
      final dist2 = du * du + dv * dv;

      if (dist2 > 4.0) continue; // beyond 2x radius, skip

      // Smooth Gaussian falloff
      final falloff = math.exp(-dist2 * 1.5);
      final bright = (intensity * falloff).round();

      if (bright < 1) continue;

      // Apply warmth tint
      final r = (bright * (1.0 + warmth)).round().clamp(0, 255);
      final g = bright.clamp(0, 255);
      final b = (bright * (1.0 - warmth)).round().clamp(0, 255);

      // Additive blend with existing pixel
      final p = image.getPixel(x, y);
      image.setPixelRgba(
        x,
        y,
        (p.r.toInt() + r).clamp(0, 255),
        (p.g.toInt() + g).clamp(0, 255),
        (p.b.toInt() + b).clamp(0, 255),
        255,
      );
    }
  }
}

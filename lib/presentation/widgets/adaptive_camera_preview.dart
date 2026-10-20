import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Renderuje podgląd z [CameraController] z deterministycznym obrotem bufora sensora
/// dla orientacji pionowej (9:16 – 1080x1920) oraz poziomej (16:9 – 1920x1080).
///
/// Rozwiązuje błąd wyścigu `ImageReaderRotatedPreview` / `DeviceOrientationManager`
/// w pakiecie `camera_android_camerax`, w wyniku którego po obrocie z pionu do poziomu
/// obraz pozostawał obrócony o 90° (pionowy) i rozciągnięty do 16:9.
class AdaptiveCameraPreview extends StatelessWidget {
  final CameraController controller;
  final bool isPortrait;
  final BoxFit fit;

  const AdaptiveCameraPreview({
    super.key,
    required this.controller,
    required this.isPortrait,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    final double pWidth = previewSize?.width ?? 1920.0;
    final double pHeight = previewSize?.height ?? 1080.0;
    final double sensorLong = pWidth > pHeight ? pWidth : pHeight;
    final double sensorShort = pWidth > pHeight ? pHeight : pWidth;

    final bool isTestEnv =
        !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

    if (kIsWeb || !Platform.isAndroid || isTestEnv) {
      final double targetWidth = isPortrait ? sensorShort : sensorLong;
      final double targetHeight = isPortrait ? sensorLong : sensorShort;
      return FittedBox(
        fit: fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: targetWidth,
          height: targetHeight,
          child: CameraPreview(controller),
        ),
      );
    }

    final int sensorOrientation = controller.description.sensorOrientation;
    final bool isFront =
        controller.description.lensDirection == CameraLensDirection.front;
    final DeviceOrientation devOrientation = controller.value.deviceOrientation;

    final int displayClockwiseDegrees;
    if (isPortrait) {
      displayClockwiseDegrees =
          devOrientation == DeviceOrientation.portraitDown ? 180 : 0;
    } else {
      displayClockwiseDegrees =
          devOrientation == DeviceOrientation.landscapeRight ? 90 : 270;
    }

    final int netRotationDegrees = isFront
        ? (sensorOrientation - displayClockwiseDegrees + 360) % 360
        : (sensorOrientation + displayClockwiseDegrees) % 360;
    final int quarterTurns = (netRotationDegrees ~/ 90) % 4;

    Widget rotatedSensorTexture = RotatedBox(
      quarterTurns: quarterTurns,
      child: SizedBox(
        width: sensorLong,
        height: sensorShort,
        child: Texture(textureId: controller.cameraId),
      ),
    );

    if (isFront) {
      rotatedSensorTexture = Transform.flip(
        flipX: true,
        child: rotatedSensorTexture,
      );
    }

    return FittedBox(
      fit: fit,
      clipBehavior: Clip.hardEdge,
      child: rotatedSensorTexture,
    );
  }
}

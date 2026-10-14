import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CameraFrameConverter {
  static const MethodChannel _channel = MethodChannel('com.goshawk.volleylive/yuv_converter');

  /// Konwertuje obiekt CameraImage do tablicy bajtów JPEG.
  /// Obsługuje akcelerację sprzętową Android YuvImage dla wszystkich formatów:
  /// - JPEG (format bezpośredni z 1 płaszczyzną)
  /// - NV21 (CameraX z 1 płaszczyzną zawierającą pełny bufor NV21)
  /// - Semi-planar NV21/NV12 (2 płaszczyzny: Y oraz VU/UV)
  /// - YUV_420_888 (3 płaszczyzny: Y, U, V)
  static Future<Uint8List?> convertYuvToJpeg(CameraImage image, {int quality = 55}) async {
    try {
      if (image.format.group == ImageFormatGroup.jpeg) {
        return image.planes.first.bytes;
      }

      // Przypadek 1: CameraX z ImageFormatGroup.nv21 dostarcza pojedynczą płaszczyznę ze scalonym buforem NV21
      if (image.planes.length == 1) {
        final result = await _channel.invokeMethod<Uint8List>('convertNv21ToJpeg', {
          'nv21': image.planes[0].bytes,
          'width': image.width,
          'height': image.height,
          'quality': quality,
        });
        return result;
      }

      // Przypadek 2: Format dwupłaszczyznowy (Y + splecione VU)
      if (image.planes.length == 2) {
        final result = await _channel.invokeMethod<Uint8List>('convertNv21TwoPlanesToJpeg', {
          'y': image.planes[0].bytes,
          'uv': image.planes[1].bytes,
          'width': image.width,
          'height': image.height,
          'yRowStride': image.planes[0].bytesPerRow,
          'uvRowStride': image.planes[1].bytesPerRow,
          'quality': quality,
        });
        return result;
      }

      // Przypadek 3: Format trójpłaszczyznowy YUV_420_888 (Y, U, V)
      if (image.planes.length >= 3) {
        final result = await _channel.invokeMethod<Uint8List>('convertYuvToJpeg', {
          'y': image.planes[0].bytes,
          'u': image.planes[1].bytes,
          'v': image.planes[2].bytes,
          'width': image.width,
          'height': image.height,
          'yRowStride': image.planes[0].bytesPerRow,
          'uvRowStride': image.planes[1].bytesPerRow,
          'uvPixelStride': image.planes[1].bytesPerPixel ?? 2,
          'quality': quality,
        });
        return result;
      }
    } catch (e) {
      debugPrint('[CameraFrameConverter] Błąd konwersji klatki do JPEG: $e');
    }
    return null;
  }
}

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CameraFrameConverter {
  static const MethodChannel _channel = MethodChannel('com.goshawk.volleylive/yuv_converter');

  /// Konwertuje obiekt CameraImage (YUV420) do tablicy bajtów JPEG.
  /// Używa akceleracji sprzętowej Android YuvImage, z bezpiecznym fallbackiem.
  static Future<Uint8List?> convertYuvToJpeg(CameraImage image, {int quality = 55}) async {
    try {
      if (image.format.group == ImageFormatGroup.jpeg) {
        return image.planes.first.bytes;
      }

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
      debugPrint('Błąd konwersji klatki YUV do JPEG: $e');
    }
    return null;
  }
}

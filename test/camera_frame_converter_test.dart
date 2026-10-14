import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volleylive/core/utils/camera_frame_converter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.goshawk.volleylive/yuv_converter');

  group('CameraFrameConverter Unit Tests', () {
    test('JPEG format returns plane bytes directly without MethodChannel invocation', () async {
      final fakeJpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final cameraImage = CameraImage.fromPlatformInterface(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.jpeg, raw: 256),
          planes: [
            CameraImagePlane(
              bytes: fakeJpegBytes,
              bytesPerRow: 1920,
              bytesPerPixel: 1,
            ),
          ],
          width: 1920,
          height: 1080,
        ),
      );

      final result = await CameraFrameConverter.convertYuvToJpeg(cameraImage);
      expect(result, equals(fakeJpegBytes));
    });

    test('Single-plane NV21 (CameraX) invokes convertNv21ToJpeg and returns JPEG bytes', () async {
      final fakeNv21Bytes = Uint8List(1920 * 1080 * 3 ~/ 2);
      final fakeExpectedJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xEE, 0x01]);
      String? invokedMethod;
      Map<dynamic, dynamic>? invokedArgs;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        invokedMethod = methodCall.method;
        invokedArgs = methodCall.arguments as Map<dynamic, dynamic>?;
        if (methodCall.method == 'convertNv21ToJpeg') {
          return fakeExpectedJpeg;
        }
        return null;
      });

      final cameraImage = CameraImage.fromPlatformInterface(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
          planes: [
            CameraImagePlane(
              bytes: fakeNv21Bytes,
              bytesPerRow: 1920,
              bytesPerPixel: 1,
            ),
          ],
          width: 1920,
          height: 1080,
        ),
      );

      final result = await CameraFrameConverter.convertYuvToJpeg(cameraImage, quality: 65);
      expect(result, equals(fakeExpectedJpeg));
      expect(invokedMethod, equals('convertNv21ToJpeg'));
      expect(invokedArgs?['width'], equals(1920));
      expect(invokedArgs?['height'], equals(1080));
      expect(invokedArgs?['quality'], equals(65));
      expect(invokedArgs?['nv21'], equals(fakeNv21Bytes));
    });

    test('Two-plane semi-planar NV21 invokes convertNv21TwoPlanesToJpeg', () async {
      final fakeYBytes = Uint8List(1920 * 1080);
      final fakeUvBytes = Uint8List(1920 * 1080 ~/ 2);
      final fakeExpectedJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xEE, 0x02]);
      String? invokedMethod;
      Map<dynamic, dynamic>? invokedArgs;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        invokedMethod = methodCall.method;
        invokedArgs = methodCall.arguments as Map<dynamic, dynamic>?;
        if (methodCall.method == 'convertNv21TwoPlanesToJpeg') {
          return fakeExpectedJpeg;
        }
        return null;
      });

      final cameraImage = CameraImage.fromPlatformInterface(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
          planes: [
            CameraImagePlane(
              bytes: fakeYBytes,
              bytesPerRow: 1920,
              bytesPerPixel: 1,
            ),
            CameraImagePlane(
              bytes: fakeUvBytes,
              bytesPerRow: 1920,
              bytesPerPixel: 2,
            ),
          ],
          width: 1920,
          height: 1080,
        ),
      );

      final result = await CameraFrameConverter.convertYuvToJpeg(cameraImage, quality: 70);
      expect(result, equals(fakeExpectedJpeg));
      expect(invokedMethod, equals('convertNv21TwoPlanesToJpeg'));
      expect(invokedArgs?['y'], equals(fakeYBytes));
      expect(invokedArgs?['uv'], equals(fakeUvBytes));
      expect(invokedArgs?['quality'], equals(70));
    });

    test('Three-plane YUV_420_888 invokes convertYuvToJpeg', () async {
      final fakeY = Uint8List(1920 * 1080);
      final fakeU = Uint8List(1920 * 1080 ~/ 4);
      final fakeV = Uint8List(1920 * 1080 ~/ 4);
      final fakeExpectedJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xEE, 0x03]);
      String? invokedMethod;
      Map<dynamic, dynamic>? invokedArgs;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        invokedMethod = methodCall.method;
        invokedArgs = methodCall.arguments as Map<dynamic, dynamic>?;
        if (methodCall.method == 'convertYuvToJpeg') {
          return fakeExpectedJpeg;
        }
        return null;
      });

      final cameraImage = CameraImage.fromPlatformInterface(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
          planes: [
            CameraImagePlane(bytes: fakeY, bytesPerRow: 1920, bytesPerPixel: 1),
            CameraImagePlane(bytes: fakeU, bytesPerRow: 960, bytesPerPixel: 1),
            CameraImagePlane(bytes: fakeV, bytesPerRow: 960, bytesPerPixel: 1),
          ],
          width: 1920,
          height: 1080,
        ),
      );

      final result = await CameraFrameConverter.convertYuvToJpeg(cameraImage, quality: 65);
      expect(result, equals(fakeExpectedJpeg));
      expect(invokedMethod, equals('convertYuvToJpeg'));
      expect(invokedArgs?['y'], equals(fakeY));
      expect(invokedArgs?['u'], equals(fakeU));
      expect(invokedArgs?['v'], equals(fakeV));
    });

    test('MethodChannel failure returns null safely without throwing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(code: 'CONVERSION_FAILED', message: 'Simulated native error');
      });

      final cameraImage = CameraImage.fromPlatformInterface(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
          planes: [
            CameraImagePlane(bytes: Uint8List(100), bytesPerRow: 10, bytesPerPixel: 1),
          ],
          width: 10,
          height: 10,
        ),
      );

      final result = await CameraFrameConverter.convertYuvToJpeg(cameraImage);
      expect(result, isNull);
    });
  });
}

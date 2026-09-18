import 'dart:ui';

enum VideoResolution {
  res720p('720p HD', 1280, 720),
  res1080p('1080p Full HD', 1920, 1080),
  res4k('4K Ultra HD', 3840, 2160);

  final String label;
  final int width;
  final int height;
  const VideoResolution(this.label, this.width, this.height);

  /// Zwraca wymiary klatki w formacie 16:9 (poziomo) lub 9:16 (pionowo)
  String getDimensionsForOrientation(bool isLandscape) {
    if (isLandscape) {
      return '${width}x$height (16:9)';
    } else {
      return '${height}x$width (9:16)';
    }
  }

  /// Zwraca etykietę proporcji
  String getAspectRatioLabel(bool isLandscape) => isLandscape ? '16:9' : '9:16';
}

enum VideoFps {
  fps30('30 FPS', 30),
  fps60('60 FPS', 60);

  final String label;
  final int fps;
  const VideoFps(this.label, this.fps);
}

enum CameraLens {
  ultraWide('0.5x Ultra Wide', 0.5),
  wide('1x Standard', 1.0),
  telephoto('2x Telephoto', 2.0);

  final String label;
  final double zoomRatio;
  const CameraLens(this.label, this.zoomRatio);
}

class CameraSettings {
  final VideoResolution resolution;
  final VideoFps fps;
  final CameraLens lens;
  final double zoom;
  final double minZoomLevel;
  final double maxZoomLevel;
  final double exposureOffset;
  final double minExposureOffset;
  final double maxExposureOffset;
  final double exposureStep;
  final bool isFocusLocked;
  final bool isExposureLocked;
  final bool isManualFocusMode;
  final Offset? focusPoint;
  final Offset? exposurePoint;
  final bool isStabilizationEnabled;
  final bool isMicrophoneEnabled;
  final double bitrateMbps;
  final bool isHudVisible;
  final String storageFolder;

  const CameraSettings({
    this.resolution = VideoResolution.res1080p,
    this.fps = VideoFps.fps60,
    this.lens = CameraLens.wide,
    this.zoom = 1.0,
    this.minZoomLevel = 1.0,
    this.maxZoomLevel = 8.0,
    this.exposureOffset = 0.0,
    this.minExposureOffset = -2.0,
    this.maxExposureOffset = 2.0,
    this.exposureStep = 0.1,
    this.isFocusLocked = false,
    this.isExposureLocked = false,
    this.isManualFocusMode = false,
    this.focusPoint,
    this.exposurePoint,
    this.isStabilizationEnabled = true,
    this.isMicrophoneEnabled = true,
    this.bitrateMbps = 8.0,
    this.isHudVisible = true,
    this.storageFolder = 'Movies/CameraMobile4Sport/mecze',
  });

  CameraSettings copyWith({
    VideoResolution? resolution,
    VideoFps? fps,
    CameraLens? lens,
    double? zoom,
    double? minZoomLevel,
    double? maxZoomLevel,
    double? exposureOffset,
    double? minExposureOffset,
    double? maxExposureOffset,
    double? exposureStep,
    bool? isFocusLocked,
    bool? isExposureLocked,
    bool? isManualFocusMode,
    Offset? focusPoint,
    Offset? exposurePoint,
    bool clearFocusPoint = false,
    bool clearExposurePoint = false,
    bool? isStabilizationEnabled,
    bool? isMicrophoneEnabled,
    double? bitrateMbps,
    bool? isHudVisible,
    String? storageFolder,
  }) {
    return CameraSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      lens: lens ?? this.lens,
      zoom: zoom ?? this.zoom,
      minZoomLevel: minZoomLevel ?? this.minZoomLevel,
      maxZoomLevel: maxZoomLevel ?? this.maxZoomLevel,
      exposureOffset: exposureOffset ?? this.exposureOffset,
      minExposureOffset: minExposureOffset ?? this.minExposureOffset,
      maxExposureOffset: maxExposureOffset ?? this.maxExposureOffset,
      exposureStep: exposureStep ?? this.exposureStep,
      isFocusLocked: isFocusLocked ?? this.isFocusLocked,
      isExposureLocked: isExposureLocked ?? this.isExposureLocked,
      isManualFocusMode: isManualFocusMode ?? this.isManualFocusMode,
      focusPoint: clearFocusPoint ? null : (focusPoint ?? this.focusPoint),
      exposurePoint: clearExposurePoint ? null : (exposurePoint ?? this.exposurePoint),
      isStabilizationEnabled: isStabilizationEnabled ?? this.isStabilizationEnabled,
      isMicrophoneEnabled: isMicrophoneEnabled ?? this.isMicrophoneEnabled,
      bitrateMbps: bitrateMbps ?? this.bitrateMbps,
      isHudVisible: isHudVisible ?? this.isHudVisible,
      storageFolder: storageFolder ?? this.storageFolder,
    );
  }

  Map<String, dynamic> toJson() => {
    'resolution': resolution.name,
    'fps': fps.name,
    'lens': lens.name,
    'zoom': zoom,
    'minZoomLevel': minZoomLevel,
    'maxZoomLevel': maxZoomLevel,
    'exposureOffset': exposureOffset,
    'minExposureOffset': minExposureOffset,
    'maxExposureOffset': maxExposureOffset,
    'exposureStep': exposureStep,
    'isFocusLocked': isFocusLocked,
    'isExposureLocked': isExposureLocked,
    'isManualFocusMode': isManualFocusMode,
    'focusPoint': focusPoint != null ? {'dx': focusPoint!.dx, 'dy': focusPoint!.dy} : null,
    'exposurePoint': exposurePoint != null ? {'dx': exposurePoint!.dx, 'dy': exposurePoint!.dy} : null,
    'isStabilizationEnabled': isStabilizationEnabled,
    'isMicrophoneEnabled': isMicrophoneEnabled,
    'bitrateMbps': bitrateMbps,
    'isHudVisible': isHudVisible,
    'storageFolder': storageFolder,
  };
}

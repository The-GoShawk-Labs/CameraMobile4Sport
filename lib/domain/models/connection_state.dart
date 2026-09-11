enum DeviceRole {
  none('Niezdefiniowana', 'none'),
  cameraPhoneA('Smartfon Kamera', 'phone_a_camera'),
  scorerPhoneB('Smartfon Sterujący', 'phone_b_controller'),
  statistician('Panel Statystyka', 'statistician'),
  singlePhoneAllInOne('Jeden Smartfon (All-in-One)', 'single_phone_all_in_one');

  final String label;
  final String idName;
  const DeviceRole(this.label, this.idName);
}

enum CameraConnectionState {
  disconnected('Rozłączony'),
  pairing('Parowanie P2P'),
  connecting('Nawiązywanie połączenia'),
  connected('Połączono'),
  reconnecting('Wznawianie połączenia...'),
  failed('Błąd połączenia');

  final String label;
  const CameraConnectionState(this.label);
}

enum StreamingState {
  idle('Bezczynny'),
  preparing('Przygotowywanie encodera'),
  connecting('Łączenie z serwerem RTMPS'),
  live('NA ŻYWO (LIVE)'),
  reconnecting('Wznawianie transmisji...'),
  stopping('Zatrzymywanie'),
  stopped('Zatrzymano'),
  failed('Błąd transmisji');

  final String label;
  const StreamingState(this.label);
}

enum RecordingState {
  idle('Bezczynny'),
  recording('NAGRYWANIE'),
  stopping('Zapisywanie pliku MP4'),
  saved('Zapisano plik'),
  failed('Błąd zapisu');

  final String label;
  const RecordingState(this.label);
}

class StreamHealthMetrics {
  final int fps;
  final double bitrateMbps;
  final int latencyMs;
  final int droppedFrames;
  final String networkQuality; // 'Doskonała', 'Dobra', 'Niestabilna'
  final bool isAudioActive;

  const StreamHealthMetrics({
    this.fps = 60,
    this.bitrateMbps = 8.2,
    this.latencyMs = 35,
    this.droppedFrames = 0,
    this.networkQuality = 'Doskonała',
    this.isAudioActive = true,
  });
}

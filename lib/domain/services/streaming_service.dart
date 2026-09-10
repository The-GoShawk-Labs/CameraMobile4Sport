import 'dart:async';
import 'package:volleylive/core/security/secure_storage_service.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/streaming_config.dart';

abstract class IStreamingService {
  Stream<StreamingState> get streamingStateStream;
  StreamingState get currentState;
  StreamingDestination get activeDestination;

  Future<bool> startLiveStream(StreamingDestination destination);
  Future<void> stopLiveStream();
}

/// Serwis nadawania RTMPS (YouTube, Meta, Generic RTMPS)
class StreamingService implements IStreamingService {
  final _stateController = StreamController<StreamingState>.broadcast();
  StreamingState _currentState = StreamingState.idle;
  StreamingDestination _activeDestination = const StreamingDestination();

  @override
  Stream<StreamingState> get streamingStateStream => _stateController.stream;

  @override
  StreamingState get currentState => _currentState;

  @override
  StreamingDestination get activeDestination => _activeDestination;

  @override
  Future<bool> startLiveStream(StreamingDestination destination) async {
    _activeDestination = destination;
    _setState(StreamingState.preparing);

    // Bezpieczna walidacja klucza streamingu w Secure Storage
    if (destination.credentialReference.isNotEmpty) {
      final key = await SecureStorageService.getCredential(destination.credentialReference);
      if (key == null || key.isEmpty) {
        _setState(StreamingState.failed);
        return false;
      }
    }

    _setState(StreamingState.connecting);
    await Future.delayed(const Duration(milliseconds: 800));

    _setState(StreamingState.live);
    return true;
  }

  @override
  Future<void> stopLiveStream() async {
    if (_currentState != StreamingState.live && _currentState != StreamingState.connecting) return;

    _setState(StreamingState.stopping);
    await Future.delayed(const Duration(milliseconds: 500));
    _setState(StreamingState.stopped);
  }

  void simulateInternetDrop() {
    if (_currentState == StreamingState.live) {
      _setState(StreamingState.reconnecting);
    }
  }

  void _setState(StreamingState state) {
    _currentState = state;
    _stateController.add(state);
  }

  void dispose() {
    _stateController.close();
  }
}

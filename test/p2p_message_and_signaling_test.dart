import 'package:flutter_test/flutter_test.dart';
import 'package:volleylive/data/models/p2p_message.dart';
import 'package:volleylive/data/repositories/p2p_connection_repository.dart';
import 'package:volleylive/data/services/local_signaling_service.dart';
import 'package:volleylive/data/services/webrtc_transport_service.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';

void main() {
  group('P2P Message & Payload Serialization Tests', () {
    test('P2PMessage scoreUpdate serialization and deserialization', () {
      const score = ScoreUpdatePayload(
        pointsA: 24,
        pointsB: 22,
        setsA: 2,
        setsB: 1,
        teamA: 'TEAM RED',
        teamB: 'TEAM BLUE',
        servingTeam: 'A',
        setNumber: 4,
        timeoutsA: 1,
        timeoutsB: 2,
        isMatchFinished: false,
      );

      final msg = P2PMessage.scoreUpdate(
        senderRole: 'phone_b_controller',
        scorePayload: score,
      );

      final jsonStr = msg.toJson();
      final parsed = P2PMessage.fromJson(jsonStr);

      expect(parsed.type, equals(P2PMessageType.scoreUpdate));
      expect(parsed.senderRole, equals('phone_b_controller'));

      final payload = ScoreUpdatePayload.fromMap(parsed.payload);
      expect(payload.pointsA, equals(24));
      expect(payload.pointsB, equals(22));
      expect(payload.setsA, equals(2));
      expect(payload.setsB, equals(1));
      expect(payload.teamA, equals('TEAM RED'));
      expect(payload.teamB, equals('TEAM BLUE'));
      expect(payload.servingTeam, equals('A'));
      expect(payload.timeoutsA, equals(1));
      expect(payload.timeoutsB, equals(2));
      expect(payload.isMatchFinished, isFalse);
    });

    test('P2PMessage cameraControl serialization and deserialization', () {
      const camPayload = CameraControlPayload(
        zoomLevel: 2.5,
        flashOn: true,
        lockAeAf: true,
        exposureCompensation: -0.5,
        resolution: '1080p',
        fps: 60,
      );

      final msg = P2PMessage.cameraControl(
        senderRole: 'phone_b_controller',
        cameraPayload: camPayload,
      );

      final jsonStr = msg.toJson();
      final parsed = P2PMessage.fromJson(jsonStr);

      expect(parsed.type, equals(P2PMessageType.cameraControl));
      final payload = CameraControlPayload.fromMap(parsed.payload);
      expect(payload.zoomLevel, equals(2.5));
      expect(payload.flashOn, isTrue);
      expect(payload.lockAeAf, isTrue);
      expect(payload.exposureCompensation, equals(-0.5));
      expect(payload.resolution, equals('1080p'));
      expect(payload.fps, equals(60));
    });

    test('P2PMessage recorderControl and heartbeat serialization', () {
      final recMsg = P2PMessage.recorderControl(
        senderRole: 'phone_b_controller',
        isRecording: true,
        matchId: 'match-123',
      );

      final recParsed = P2PMessage.fromJson(recMsg.toJson());
      expect(recParsed.type, equals(P2PMessageType.recorderControl));
      expect(recParsed.payload['isRecording'], isTrue);
      expect(recParsed.payload['matchId'], equals('match-123'));

      final hbMsg = P2PMessage.heartbeat(
        senderRole: 'phone_a_camera',
        batteryLevel: 95,
        thermalState: 'normal',
      );

      final hbParsed = P2PMessage.fromJson(hbMsg.toJson());
      expect(hbParsed.type, equals(P2PMessageType.heartbeat));
      expect(hbParsed.payload['batteryLevel'], equals(95));
      expect(hbParsed.payload['thermalState'], equals('normal'));
    });

    test('P2PMessage WebRTC SDP and ICE Candidate serialization', () {
      final sdpMsg = P2PMessage.sdpOffer(
        senderRole: 'phone_a_camera',
        sdp: 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n',
      );

      final parsedSdp = P2PMessage.fromJson(sdpMsg.toJson());
      expect(parsedSdp.type, equals(P2PMessageType.sdpOffer));
      expect(parsedSdp.payload['type'], equals('offer'));
      expect(parsedSdp.payload['sdp'], contains('v=0'));

      final iceMsg = P2PMessage.iceCandidate(
        senderRole: 'phone_b_controller',
        candidate: 'candidate:1 1 UDP 2130706431 192.168.1.100 50000 typ host',
        sdpMid: 'video',
        sdpMLineIndex: 0,
      );

      final parsedIce = P2PMessage.fromJson(iceMsg.toJson());
      expect(parsedIce.type, equals(P2PMessageType.iceCandidate));
      expect(parsedIce.payload['sdpMid'], equals('video'));
      expect(parsedIce.payload['sdpMLineIndex'], equals(0));
    });
  });

  group('Signaling & Transport Unit Tests', () {
    test('LocalSignalingService start, connect and transmit messages', () async {
      final server = LocalSignalingService();
      final client = LocalSignalingService();

      // Wybierz losowy wolny port testowy
      const testPort = 18991;
      await server.startLocalServer(port: testPort);
      expect(server.isConnected, isFalse); // Serwer czeka na połączenie klienta

      final serverReceived = <P2PMessage>[];
      final clientReceived = <P2PMessage>[];

      server.incomingMessages.listen(serverReceived.add);
      client.incomingMessages.listen(clientReceived.add);

      await client.connect('127.0.0.1', port: testPort);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(client.isConnected, isTrue);
      expect(server.isConnected, isTrue);

      // Klient wysyła komunikat do serwera
      client.sendMessage(
        const P2PMessage(
          id: 'test_1',
          type: P2PMessageType.syncState,
          senderRole: 'phone_a_camera',
          timestamp: 1000,
          payload: {'status': 'ready'},
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));
      expect(serverReceived.length, equals(1));
      expect(serverReceived.first.id, equals('test_1'));
      expect(serverReceived.first.payload['status'], equals('ready'));

      // Serwer wysyła komunikat do klienta
      server.sendMessage(
        const P2PMessage(
          id: 'test_2',
          type: P2PMessageType.heartbeatAck,
          senderRole: 'phone_b_controller',
          timestamp: 2000,
          payload: {'ack': true},
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));
      expect(clientReceived.length, equals(1));
      expect(clientReceived.first.id, equals('test_2'));

      await client.disconnect();
      await server.stopServer();
      server.dispose();
      client.dispose();
    });

    test('P2PConnectionProvider handles roles and message dispatch', () async {
      final transport = WebRtcTransportService();
      final repo = P2PConnectionRepository(transportService: transport);
      final provider = P2PConnectionProvider(repository: repo);

      expect(provider.currentRole, equals(DeviceRole.none));
      expect(provider.connectionState, equals(CameraConnectionState.disconnected));

      provider.selectRole(DeviceRole.cameraPhoneA);
      expect(provider.currentRole, equals(DeviceRole.cameraPhoneA));
      expect(provider.currentRole.idName, equals('phone_a_camera'));

      provider.selectRole(DeviceRole.scorerPhoneB);
      expect(provider.currentRole, equals(DeviceRole.scorerPhoneB));
      expect(provider.currentRole.idName, equals('phone_b_controller'));

      provider.dispose();
    });
  });
}

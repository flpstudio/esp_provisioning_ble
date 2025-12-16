import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:esp_provisioning_ble/src/protos/generated/wifi_scan.pb.dart';
import 'package:esp_provisioning_ble/src/protos/generated/wifi_config.pb.dart';
import 'package:esp_provisioning_ble/src/protos/generated/wifi_constants.pb.dart';
import 'package:esp_provisioning_ble/src/protos/generated/constants.pbenum.dart';
import 'package:esp_provisioning_ble/src/protos/generated/session.pb.dart';
import 'package:esp_provisioning_ble/src/protos/generated/sec1.pb.dart';

void main() {
  group('Protobuf Operations Tests', () {
    group('WiFi Scan Payloads', () {
      test('should serialize and deserialize WiFi scan start command', () {
        final originalPayload = WiFiScanPayload();
        originalPayload.msg = WiFiScanMsgType.TypeCmdScanStart;

        final scanStart = CmdScanStart();
        scanStart.blocking = true;
        scanStart.passive = false;
        scanStart.groupChannels = 5;
        scanStart.periodMs = 1000;
        originalPayload.cmdScanStart = scanStart;

        // Serialize
        final serialized = originalPayload.writeToBuffer();
        expect(serialized, isNotEmpty);

        // Deserialize
        final deserializedPayload = WiFiScanPayload.fromBuffer(serialized);
        expect(
            deserializedPayload.msg, equals(WiFiScanMsgType.TypeCmdScanStart));
        expect(deserializedPayload.cmdScanStart.blocking, isTrue);
        expect(deserializedPayload.cmdScanStart.passive, isFalse);
        expect(deserializedPayload.cmdScanStart.groupChannels, equals(5));
        expect(deserializedPayload.cmdScanStart.periodMs, equals(1000));
      });

      test('should handle WiFi scan results with network entries', () {
        final originalPayload = WiFiScanPayload();
        originalPayload.msg = WiFiScanMsgType.TypeRespScanResult;

        final scanResult = RespScanResult();

        // Add test networks
        final network1 = WiFiScanResult();
        network1.ssid = utf8.encode('TestNetwork');
        network1.rssi = -45;
        network1.auth = WifiAuthMode.WPA2_PSK;
        network1.channel = 6;
        scanResult.entries.add(network1);

        final network2 = WiFiScanResult();
        network2.ssid = utf8.encode('OpenNetwork');
        network2.rssi = -60;
        network2.auth = WifiAuthMode.Open;
        network2.channel = 11;
        scanResult.entries.add(network2);

        originalPayload.respScanResult = scanResult;

        // Serialize and deserialize
        final serialized = originalPayload.writeToBuffer();
        final deserializedPayload = WiFiScanPayload.fromBuffer(serialized);

        expect(deserializedPayload.msg,
            equals(WiFiScanMsgType.TypeRespScanResult));
        expect(deserializedPayload.respScanResult.entries.length, equals(2));

        final deserializedNetwork1 =
            deserializedPayload.respScanResult.entries[0];
        expect(utf8.decode(deserializedNetwork1.ssid), equals('TestNetwork'));
        expect(deserializedNetwork1.rssi, equals(-45));
        expect(deserializedNetwork1.auth, equals(WifiAuthMode.WPA2_PSK));
        expect(deserializedNetwork1.channel, equals(6));

        final deserializedNetwork2 =
            deserializedPayload.respScanResult.entries[1];
        expect(utf8.decode(deserializedNetwork2.ssid), equals('OpenNetwork'));
        expect(deserializedNetwork2.rssi, equals(-60));
        expect(deserializedNetwork2.auth, equals(WifiAuthMode.Open));
        expect(deserializedNetwork2.channel, equals(11));
      });

      test('should handle scan status response', () {
        final originalPayload = WiFiScanPayload();
        originalPayload.msg = WiFiScanMsgType.TypeRespScanStatus;

        final scanStatus = RespScanStatus();
        scanStatus.scanFinished = true;
        scanStatus.resultCount = 10;
        originalPayload.respScanStatus = scanStatus;

        final serialized = originalPayload.writeToBuffer();
        final deserializedPayload = WiFiScanPayload.fromBuffer(serialized);

        expect(deserializedPayload.msg,
            equals(WiFiScanMsgType.TypeRespScanStatus));
        expect(deserializedPayload.respScanStatus.scanFinished, isTrue);
        expect(deserializedPayload.respScanStatus.resultCount, equals(10));
      });
    });

    group('WiFi Configuration Payloads', () {
      test('should serialize WiFi credentials correctly', () {
        final originalPayload = WiFiConfigPayload();
        originalPayload.msg = WiFiConfigMsgType.TypeCmdSetConfig;

        final setConfig = CmdSetConfig();
        setConfig.ssid = utf8.encode('MyWiFiNetwork');
        setConfig.passphrase = utf8.encode('MySecretPassword123');
        originalPayload.cmdSetConfig = setConfig;

        final serialized = originalPayload.writeToBuffer();
        final deserializedPayload = WiFiConfigPayload.fromBuffer(serialized);

        expect(deserializedPayload.msg,
            equals(WiFiConfigMsgType.TypeCmdSetConfig));
        expect(utf8.decode(deserializedPayload.cmdSetConfig.ssid),
            equals('MyWiFiNetwork'));
        expect(utf8.decode(deserializedPayload.cmdSetConfig.passphrase),
            equals('MySecretPassword123'));
      });

      test('should handle configuration response status', () {
        final originalPayload = WiFiConfigPayload();
        originalPayload.msg = WiFiConfigMsgType.TypeRespSetConfig;

        final setConfigResp = RespSetConfig();
        setConfigResp.status = Status.Success;
        originalPayload.respSetConfig = setConfigResp;

        final serialized = originalPayload.writeToBuffer();
        final deserializedPayload = WiFiConfigPayload.fromBuffer(serialized);

        expect(deserializedPayload.msg,
            equals(WiFiConfigMsgType.TypeRespSetConfig));
        expect(
            deserializedPayload.respSetConfig.status, equals(Status.Success));
      });

      test('should handle connection status with IP address', () {
        final originalPayload = WiFiConfigPayload();
        originalPayload.msg = WiFiConfigMsgType.TypeRespGetStatus;

        final getStatusResp = RespGetStatus();
        getStatusResp.staState = WifiStationState.Connected;

        final connectedState = WifiConnectedState();
        connectedState.ip4Addr = '192.168.1.100';
        connectedState.authMode = WifiAuthMode.WPA2_PSK;
        connectedState.ssid = utf8.encode('ConnectedNetwork');
        connectedState.channel = 6;
        getStatusResp.connected = connectedState;

        originalPayload.respGetStatus = getStatusResp;

        final serialized = originalPayload.writeToBuffer();
        final deserializedPayload = WiFiConfigPayload.fromBuffer(serialized);

        expect(deserializedPayload.msg,
            equals(WiFiConfigMsgType.TypeRespGetStatus));
        expect(deserializedPayload.respGetStatus.staState,
            equals(WifiStationState.Connected));
        expect(deserializedPayload.respGetStatus.connected.ip4Addr,
            equals('192.168.1.100'));
        expect(deserializedPayload.respGetStatus.connected.authMode,
            equals(WifiAuthMode.WPA2_PSK));
        expect(utf8.decode(deserializedPayload.respGetStatus.connected.ssid),
            equals('ConnectedNetwork'));
      });

      test('should handle connection failure with reason', () {
        final originalPayload = WiFiConfigPayload();
        originalPayload.msg = WiFiConfigMsgType.TypeRespGetStatus;

        final getStatusResp = RespGetStatus();
        getStatusResp.staState = WifiStationState.ConnectionFailed;
        getStatusResp.failReason = WifiConnectFailedReason.AuthError;

        originalPayload.respGetStatus = getStatusResp;

        final serialized = originalPayload.writeToBuffer();
        final deserializedPayload = WiFiConfigPayload.fromBuffer(serialized);

        expect(deserializedPayload.msg,
            equals(WiFiConfigMsgType.TypeRespGetStatus));
        expect(deserializedPayload.respGetStatus.staState,
            equals(WifiStationState.ConnectionFailed));
        expect(deserializedPayload.respGetStatus.failReason,
            equals(WifiConnectFailedReason.AuthError));
      });
    });

    group('Session Payloads', () {
      test('should serialize session data for security handshake', () {
        final originalSession = SessionData();
        originalSession.secVer = SecSchemeVersion.SecScheme1;

        final sec1Payload = Sec1Payload();
        final sessionCmd0 = SessionCmd0();
        sessionCmd0.clientPubkey = List.generate(32, (i) => i % 256);
        sec1Payload.sc0 = sessionCmd0;
        originalSession.sec1 = sec1Payload;

        final serialized = originalSession.writeToBuffer();
        final deserializedSession = SessionData.fromBuffer(serialized);

        expect(deserializedSession.secVer, equals(SecSchemeVersion.SecScheme1));
        expect(deserializedSession.sec1.sc0.clientPubkey.length, equals(32));
        expect(deserializedSession.sec1.sc0.clientPubkey[0], equals(0));
        expect(deserializedSession.sec1.sc0.clientPubkey[31], equals(31));
      });

      test('should handle session response with device keys', () {
        final originalSession = SessionData();
        originalSession.secVer = SecSchemeVersion.SecScheme1;

        final sec1Payload = Sec1Payload();
        final sessionResp0 = SessionResp0();
        sessionResp0.devicePubkey = List.generate(32, (i) => 255 - i);
        sessionResp0.deviceRandom = List.generate(16, (i) => i * 2);
        sec1Payload.sr0 = sessionResp0;
        originalSession.sec1 = sec1Payload;

        final serialized = originalSession.writeToBuffer();
        final deserializedSession = SessionData.fromBuffer(serialized);

        expect(deserializedSession.sec1.sr0.devicePubkey.length, equals(32));
        expect(deserializedSession.sec1.sr0.devicePubkey[0], equals(255));
        expect(deserializedSession.sec1.sr0.devicePubkey[31], equals(224));
        expect(deserializedSession.sec1.sr0.deviceRandom.length, equals(16));
        expect(deserializedSession.sec1.sr0.deviceRandom[0], equals(0));
        expect(deserializedSession.sec1.sr0.deviceRandom[15], equals(30));
      });
    });

    group('Error Cases and Edge Conditions', () {
      test('should handle empty payloads gracefully', () {
        final emptyPayload = WiFiScanPayload();
        final serialized = emptyPayload.writeToBuffer();
        final deserialized = WiFiScanPayload.fromBuffer(serialized);

        expect(deserialized.msg,
            equals(WiFiScanMsgType.TypeCmdScanStart)); // Default value
      });

      test('should handle malformed data gracefully', () {
        final invalidData = Uint8List.fromList([0xFF, 0xFF, 0xFF]);

        expect(() => WiFiScanPayload.fromBuffer(invalidData),
            throwsA(isA<Exception>()));
      });

      test('should handle large SSID names correctly', () {
        final longSSID = 'A' * 32; // Maximum WiFi SSID length

        final payload = WiFiConfigPayload();
        payload.msg = WiFiConfigMsgType.TypeCmdSetConfig;

        final setConfig = CmdSetConfig();
        setConfig.ssid = utf8.encode(longSSID);
        setConfig.passphrase = utf8.encode('password');
        payload.cmdSetConfig = setConfig;

        final serialized = payload.writeToBuffer();
        final deserialized = WiFiConfigPayload.fromBuffer(serialized);

        expect(utf8.decode(deserialized.cmdSetConfig.ssid), equals(longSSID));
        expect(utf8.decode(deserialized.cmdSetConfig.ssid).length, equals(32));
      });

      test('should handle unicode characters in SSID', () {
        const unicodeSSID = 'Test-WiFi-🏠-网络';

        final payload = WiFiConfigPayload();
        payload.msg = WiFiConfigMsgType.TypeCmdSetConfig;

        final setConfig = CmdSetConfig();
        setConfig.ssid = utf8.encode(unicodeSSID);
        setConfig.passphrase = utf8.encode('password123');
        payload.cmdSetConfig = setConfig;

        final serialized = payload.writeToBuffer();
        final deserialized = WiFiConfigPayload.fromBuffer(serialized);

        expect(
            utf8.decode(deserialized.cmdSetConfig.ssid), equals(unicodeSSID));
      });

      test('should handle all WiFi authentication modes', () {
        final authModes = [
          WifiAuthMode.Open,
          WifiAuthMode.WEP,
          WifiAuthMode.WPA_PSK,
          WifiAuthMode.WPA2_PSK,
          WifiAuthMode.WPA_WPA2_PSK,
          WifiAuthMode.WPA2_ENTERPRISE,
        ];

        for (final authMode in authModes) {
          final payload = WiFiScanPayload();
          payload.msg = WiFiScanMsgType.TypeRespScanResult;

          final scanResult = RespScanResult();
          final network = WiFiScanResult();
          network.ssid = utf8.encode('TestNetwork');
          network.rssi = -50;
          network.auth = authMode;
          scanResult.entries.add(network);
          payload.respScanResult = scanResult;

          final serialized = payload.writeToBuffer();
          final deserialized = WiFiScanPayload.fromBuffer(serialized);

          expect(deserialized.respScanResult.entries[0].auth, equals(authMode));
        }
      });
    });
  });
}

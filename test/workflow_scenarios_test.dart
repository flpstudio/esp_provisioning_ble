import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:esp_provisioning_ble/src/esp_prov.dart';
import 'package:esp_provisioning_ble/src/transport.dart';
import 'package:esp_provisioning_ble/src/security.dart';
import 'package:esp_provisioning_ble/src/connection_models.dart';
import 'package:esp_provisioning_ble/src/protos/generated/session.pb.dart';

void main() {
  group('ESP Provisioning Workflow Scenarios', () {
    group('WiFi Scanning Workflow', () {
      test('should handle complete scan workflow with pagination', () async {
        final espProv = MockEspProv();

        // Simulate a large number of networks requiring pagination
        final networks = List.generate(
            10,
            (i) => WifiAP(
                  ssid: 'Network$i',
                  rssi: -50 - i,
                  private: i % 2 == 0,
                ));

        espProv.mockNetworks = networks;

        final result = await espProv.scan();

        expect(result.length, equals(10));
        expect(result[0].ssid, equals('Network0'));
        expect(result[9].ssid, equals('Network9'));
        expect(result[0].private, isTrue);
        expect(result[1].private, isFalse);
      });

      test('should handle scan with no networks found', () async {
        final espProv = MockEspProv();
        espProv.mockNetworks = [];

        final result = await espProv.scan();

        expect(result, isEmpty);
      });

      test('should handle scan failure scenarios', () async {
        final espProv = MockEspProv();
        espProv.shouldFailScan = true;

        expect(() => espProv.scan(), throwsException);
      });

      test('should validate scan parameters correctly', () async {
        final espProv = MockEspProv();

        // Test with custom parameters
        await espProv.scan(
          blocking: false,
          passive: true,
          groupChannels: 10,
          periodMs: 2000,
        );

        expect(espProv.lastScanParams['blocking'], isFalse);
        expect(espProv.lastScanParams['passive'], isTrue);
        expect(espProv.lastScanParams['groupChannels'], equals(10));
        expect(espProv.lastScanParams['periodMs'], equals(2000));
      });
    });

    group('WiFi Configuration Workflow', () {
      test('should handle successful WiFi configuration workflow', () async {
        final espProv = MockEspProv();

        // Test send configuration
        final configResult = await espProv.sendWifiConfig(
          ssid: 'MyHomeWiFi',
          password: 'SecurePassword123',
        );
        expect(configResult, isTrue);

        // Test apply configuration
        final applyResult = await espProv.applyWifiConfig();
        expect(applyResult, isTrue);

        // Verify stored configuration
        expect(espProv.lastWifiConfig['ssid'], equals('MyHomeWiFi'));
        expect(espProv.lastWifiConfig['password'], equals('SecurePassword123'));
      });

      test('should handle configuration failure scenarios', () async {
        final espProv = MockEspProv();
        espProv.shouldFailConfig = true;

        final configResult = await espProv.sendWifiConfig(
          ssid: 'FailingNetwork',
          password: 'badpassword',
        );
        expect(configResult, isFalse);
      });

      test('should handle unicode SSID and password correctly', () async {
        final espProv = MockEspProv();

        const unicodeSSID = 'WiFi-🏠-网络';
        const unicodePassword = 'パスワード123';

        final result = await espProv.sendWifiConfig(
          ssid: unicodeSSID,
          password: unicodePassword,
        );

        expect(result, isTrue);
        expect(espProv.lastWifiConfig['ssid'], equals(unicodeSSID));
        expect(espProv.lastWifiConfig['password'], equals(unicodePassword));
      });

      test('should handle empty SSID or password gracefully', () async {
        final espProv = MockEspProv();

        expect(
          () => espProv.sendWifiConfig(ssid: '', password: 'password'),
          throwsArgumentError,
        );

        expect(
          () => espProv.sendWifiConfig(ssid: 'ssid', password: ''),
          throwsArgumentError,
        );
      });
    });

    group('Connection Status Monitoring', () {
      test('should handle all connection states correctly', () async {
        final espProv = MockEspProv();

        // Test Connected state
        espProv.mockConnectionStatus = ConnectionStatus(
          state: WifiConnectionState.Connected,
          deviceIp: '192.168.1.100',
        );
        var status = await espProv.getStatus();
        expect(status.state, equals(WifiConnectionState.Connected));
        expect(status.deviceIp, equals('192.168.1.100'));

        // Test Connecting state
        espProv.mockConnectionStatus = ConnectionStatus(
          state: WifiConnectionState.Connecting,
        );
        status = await espProv.getStatus();
        expect(status.state, equals(WifiConnectionState.Connecting));
        expect(status.deviceIp, isNull);

        // Test Disconnected state
        espProv.mockConnectionStatus = ConnectionStatus(
          state: WifiConnectionState.Disconnected,
        );
        status = await espProv.getStatus();
        expect(status.state, equals(WifiConnectionState.Disconnected));

        // Test Connection Failed with Auth Error
        espProv.mockConnectionStatus = ConnectionStatus(
          state: WifiConnectionState.ConnectionFailed,
          failedReason: WifiConnectFailedReason.AuthError,
        );
        status = await espProv.getStatus();
        expect(status.state, equals(WifiConnectionState.ConnectionFailed));
        expect(status.failedReason, equals(WifiConnectFailedReason.AuthError));

        // Test Connection Failed with Network Not Found
        espProv.mockConnectionStatus = ConnectionStatus(
          state: WifiConnectionState.ConnectionFailed,
          failedReason: WifiConnectFailedReason.NetworkNotFound,
        );
        status = await espProv.getStatus();
        expect(status.state, equals(WifiConnectionState.ConnectionFailed));
        expect(status.failedReason,
            equals(WifiConnectFailedReason.NetworkNotFound));
      });

      test('should handle status polling during connection', () async {
        final espProv = MockEspProv();
        final statusChanges = [
          ConnectionStatus(state: WifiConnectionState.Connecting),
          ConnectionStatus(state: WifiConnectionState.Connecting),
          ConnectionStatus(
            state: WifiConnectionState.Connected,
            deviceIp: '192.168.1.100',
          ),
        ];

        for (final expectedStatus in statusChanges) {
          espProv.mockConnectionStatus = expectedStatus;
          final actualStatus = await espProv.getStatus();
          expect(actualStatus.state, equals(expectedStatus.state));
          expect(actualStatus.deviceIp, equals(expectedStatus.deviceIp));
        }
      });
    });

    group('Custom Data Exchange', () {
      test('should handle small custom data correctly', () async {
        final espProv = MockEspProv();
        final testData = Uint8List.fromList(utf8.encode('Hello ESP32'));

        final response = await espProv.sendReceiveCustomData(testData);

        expect(response, isNotNull);
        expect(response.length, greaterThan(0));
        // Extract the original data (remove header 0xAA and footer 0xBB)
        final originalData = response.sublist(1, response.length - 1);
        expect(utf8.decode(originalData), equals('Hello ESP32'));
      });

      test('should handle large custom data with chunking', () async {
        final espProv = MockEspProv();
        final largeData =
            Uint8List.fromList(List.generate(2048, (i) => i % 256));

        final response = await espProv.sendReceiveCustomData(
          largeData,
          packageSize: 128,
        );

        expect(response, isNotNull);
        expect(response.length, greaterThan(0));
        expect(espProv.customDataChunks.length,
            equals(16)); // 2048 / 128 = 16 chunks
      });

      test('should handle binary custom data correctly', () async {
        final espProv = MockEspProv();
        final binaryData = Uint8List.fromList([
          0x00,
          0xFF,
          0xAA,
          0x55,
          0x01,
          0x02,
          0x03,
          0x04,
          0xDE,
          0xAD,
          0xBE,
          0xEF,
          0xCA,
          0xFE,
          0xBA,
          0xBE
        ]);

        final response = await espProv.sendReceiveCustomData(binaryData);

        expect(response, isNotNull);
        // Extract the original data (remove header 0xAA and footer 0xBB)
        final originalData = response.sublist(1, response.length - 1);
        expect(originalData[0], equals(0x00));
        expect(originalData[1], equals(0xFF));
        expect(originalData.length, equals(binaryData.length));
      });

      test('should handle empty custom data', () async {
        final espProv = MockEspProv();
        final emptyData = Uint8List(0);

        final response = await espProv.sendReceiveCustomData(emptyData);

        expect(response, isNotNull);
        expect(response.length, equals(0));
      });
    });

    group('Session Management', () {
      test('should handle successful session establishment', () async {
        final espProv = MockEspProv();

        final result = await espProv.establishSession();

        expect(result, equals(EstablishSessionStatus.connected));
      });

      test('should handle session key mismatch', () async {
        final espProv = MockEspProv();
        espProv.mockSessionStatus = EstablishSessionStatus.keymismatch;

        final result = await espProv.establishSession();

        expect(result, equals(EstablishSessionStatus.keymismatch));
      });

      test('should handle session disconnection', () async {
        final espProv = MockEspProv();
        espProv.mockSessionStatus = EstablishSessionStatus.disconnected;

        final result = await espProv.establishSession();

        expect(result, equals(EstablishSessionStatus.disconnected));
      });
    });

    group('Error Handling and Edge Cases', () {
      test('should handle network timeout scenarios', () async {
        final espProv = MockEspProv();
        espProv.shouldTimeout = true;

        expect(() => espProv.scan(), throwsA(isA<TimeoutException>()));
      });

      test('should handle malformed response data', () async {
        final espProv = MockEspProv();
        espProv.shouldReturnMalformedData = true;

        expect(() => espProv.scan(), throwsA(isA<FormatException>()));
      });

      test('should handle proper resource cleanup', () async {
        final espProv = MockEspProv();

        // Perform some operations
        await espProv.scan();
        await espProv.sendWifiConfig(ssid: 'test', password: 'test');

        // Dispose should clean up resources
        await espProv.dispose();

        expect(espProv.isDisposed, isTrue);
      });
    });
  });
}

// Mock implementation for testing workflow scenarios
class MockEspProv extends EspProv {
  List<WifiAP> mockNetworks = [];
  ConnectionStatus mockConnectionStatus =
      ConnectionStatus(state: WifiConnectionState.Disconnected);
  EstablishSessionStatus mockSessionStatus = EstablishSessionStatus.connected;
  Map<String, dynamic> lastScanParams = {};
  Map<String, String> lastWifiConfig = {};
  List<Uint8List> customDataChunks = [];

  bool shouldFailScan = false;
  bool shouldFailConfig = false;
  bool shouldTimeout = false;
  bool shouldReturnMalformedData = false;
  bool isDisposed = false;

  MockEspProv() : super(transport: MockTransport(), security: MockSecurity());

  @override
  Future<List<WifiAP>> scan({
    bool blocking = true,
    bool passive = false,
    int groupChannels = 5,
    int periodMs = 0,
  }) async {
    lastScanParams = {
      'blocking': blocking,
      'passive': passive,
      'groupChannels': groupChannels,
      'periodMs': periodMs,
    };

    if (shouldTimeout) {
      throw TimeoutException('Network timeout', const Duration(seconds: 30));
    }

    if (shouldReturnMalformedData) {
      throw const FormatException('Malformed response data');
    }

    if (shouldFailScan) {
      throw Exception('Scan failed');
    }

    return mockNetworks;
  }

  @override
  Future<bool> sendWifiConfig(
      {required String ssid, required String password}) async {
    if (ssid.isEmpty || password.isEmpty) {
      throw ArgumentError('SSID and password cannot be empty');
    }

    lastWifiConfig = {'ssid': ssid, 'password': password};

    if (shouldFailConfig) {
      return false;
    }

    return true;
  }

  @override
  Future<bool> applyWifiConfig() async {
    if (shouldFailConfig) {
      return false;
    }
    return true;
  }

  @override
  Future<ConnectionStatus> getStatus() async {
    return mockConnectionStatus;
  }

  @override
  Future<Uint8List> sendReceiveCustomData(Uint8List data,
      {int packageSize = 256}) async {
    // Simulate chunking
    customDataChunks.clear();
    for (int i = 0; i < data.length; i += packageSize) {
      final end =
          (i + packageSize < data.length) ? i + packageSize : data.length;
      customDataChunks.add(data.sublist(i, end));
    }

    // Echo back the data with some modification for testing
    if (data.isEmpty) {
      return Uint8List(0);
    }

    return Uint8List.fromList([0xAA] + data.toList() + [0xBB]);
  }

  @override
  Future<EstablishSessionStatus> establishSession() async {
    return mockSessionStatus;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}

// Mock implementations extending the proper abstract classes
class MockTransport extends ProvTransport {
  @override
  Future<bool> connect() async => true;

  @override
  Future<bool> disconnect() async => true;

  @override
  Future<bool> checkConnect() async => true;

  @override
  Future<Uint8List> sendReceive(String epName, Uint8List data) async {
    return Uint8List.fromList([0xAA] + data.toList() + [0xBB]);
  }
}

class MockSecurity extends ProvSecurity {
  @override
  Future<Uint8List> encrypt(Uint8List data) async => data;

  @override
  Future<Uint8List> decrypt(Uint8List data) async => data;

  @override
  Future<SessionData?> securitySession(SessionData responseData) async => null;
}

// Custom exceptions for testing
class TimeoutException implements Exception {
  final String message;
  final Duration timeout;

  TimeoutException(this.message, this.timeout);

  @override
  String toString() => 'TimeoutException: $message (timeout: $timeout)';
}

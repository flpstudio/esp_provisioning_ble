import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:esp_provisioning_ble/src/transport.dart';

void main() {
  group('ProvTransport Contract Tests', () {
    late TestProvTransport transport;

    setUp(() {
      transport = TestProvTransport();
    });

    group('Connection Management', () {
      test('should handle connection lifecycle correctly', () async {
        // Initially disconnected
        expect(await transport.checkConnect(), isFalse);

        // Connect should return success
        final connectResult = await transport.connect();
        expect(connectResult, isTrue);
        expect(await transport.checkConnect(), isTrue);

        // Disconnect should return success
        final disconnectResult = await transport.disconnect();
        expect(disconnectResult, isTrue);
        expect(await transport.checkConnect(), isFalse);
      });

      test('should handle multiple connect/disconnect cycles', () async {
        for (int i = 0; i < 3; i++) {
          expect(await transport.connect(), isTrue);
          expect(await transport.checkConnect(), isTrue);

          expect(await transport.disconnect(), isTrue);
          expect(await transport.checkConnect(), isFalse);
        }
      });

      test('should handle redundant connection attempts', () async {
        // Connect first time
        expect(await transport.connect(), isTrue);
        expect(await transport.checkConnect(), isTrue);

        // Connect again should still work
        expect(await transport.connect(), isTrue);
        expect(await transport.checkConnect(), isTrue);
      });

      test('should handle redundant disconnection attempts', () async {
        // Disconnect when already disconnected
        expect(await transport.checkConnect(), isFalse);
        expect(await transport.disconnect(), isTrue);
        expect(await transport.checkConnect(), isFalse);
      });
    });

    group('Data Exchange', () {
      test('should send and receive data when connected', () async {
        await transport.connect();

        final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final result = await transport.sendReceive('test-endpoint', testData);

        expect(result, isNotNull);
        expect(result.length, greaterThan(0));
        expect(result.length,
            equals(testData.length + 2)); // Header + data + footer
      });

      test('should throw when sending data while disconnected', () async {
        expect(await transport.checkConnect(), isFalse);

        final testData = Uint8List.fromList([1, 2, 3]);

        expect(
          () => transport.sendReceive('test-endpoint', testData),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle different endpoint names', () async {
        await transport.connect();

        final testData = Uint8List.fromList([1, 2, 3]);
        final endpoints = [
          'prov-scan',
          'prov-config',
          'prov-session',
          'custom-data'
        ];

        for (final endpoint in endpoints) {
          final result = await transport.sendReceive(endpoint, testData);
          expect(result, isNotNull);
          expect(result.length, greaterThan(0));
        }
      });

      test('should handle empty data correctly', () async {
        await transport.connect();

        final emptyData = Uint8List(0);
        final result = await transport.sendReceive('test-endpoint', emptyData);

        expect(result, isNotNull);
        expect(result.length, equals(2)); // Just header and footer
      });

      test('should handle large data correctly', () async {
        await transport.connect();

        final largeData =
            Uint8List.fromList(List.generate(1024, (i) => i % 256));
        final result = await transport.sendReceive('test-endpoint', largeData);

        expect(result, isNotNull);
        expect(result.length, equals(largeData.length + 2));
      });
    });

    group('Error Scenarios', () {
      test('should handle connection failures gracefully', () async {
        transport.shouldFailConnect = true;

        final result = await transport.connect();
        expect(result, isFalse);
        expect(await transport.checkConnect(), isFalse);
      });

      test('should handle send/receive failures when connected', () async {
        await transport.connect();
        transport.shouldFailSendReceive = true;

        final testData = Uint8List.fromList([1, 2, 3]);

        expect(
          () => transport.sendReceive('test-endpoint', testData),
          throwsA(isA<Exception>()),
        );
      });

      test('should maintain connection state after failed operations',
          () async {
        await transport.connect();
        expect(await transport.checkConnect(), isTrue);

        transport.shouldFailSendReceive = true;

        try {
          await transport.sendReceive('test', Uint8List.fromList([1, 2, 3]));
        } catch (e) {
          // Expected to fail
        }

        // Connection should still be active
        expect(await transport.checkConnect(), isTrue);
      });
    });
  });
}

// Test implementation that validates the ProvTransport contract
class TestProvTransport extends ProvTransport {
  bool _isConnected = false;
  bool shouldFailConnect = false;
  bool shouldFailSendReceive = false;

  @override
  Future<bool> connect() async {
    if (shouldFailConnect) {
      return false;
    }
    _isConnected = true;
    return true;
  }

  @override
  Future<bool> disconnect() async {
    _isConnected = false;
    return true;
  }

  @override
  Future<bool> checkConnect() async {
    return _isConnected;
  }

  @override
  Future<Uint8List> sendReceive(String epName, Uint8List data) async {
    if (!_isConnected) {
      throw Exception('Transport not connected');
    }

    if (shouldFailSendReceive) {
      throw Exception('Send/receive operation failed');
    }

    // Echo back the data with header and footer for testing
    return Uint8List.fromList([0xAA] + data.toList() + [0xBB]);
  }
}

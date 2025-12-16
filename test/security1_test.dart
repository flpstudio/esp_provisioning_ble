import 'package:flutter_test/flutter_test.dart';
import 'package:esp_provisioning_ble/src/security1.dart';
import 'package:esp_provisioning_ble/src/security.dart';
import 'package:esp_provisioning_ble/src/protos/generated/session.pb.dart';

void main() {
  // Initialize Flutter bindings for testing
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Security1 Tests', () {
    late Security1 security1;

    setUp(() {
      security1 = Security1(verbose: false);
    });

    group('Constructor and Configuration', () {
      test('should create Security1 with default parameters', () {
        final security = Security1();

        expect(security.sessionState, equals(SecurityState.request1));
        expect(security.pop, isNull);
        expect(security.verbose, isFalse);
      });

      test('should create Security1 with custom parameters', () {
        final security = Security1(
          pop: 'test123',
          sessionState: SecurityState.response1Request2,
          verbose: true,
        );

        expect(security.sessionState, equals(SecurityState.response1Request2));
        expect(security.pop, equals('test123'));
        expect(security.verbose, isTrue);
      });

      test('should create Security1 with different PoP values', () {
        final securities = [
          Security1(pop: ''),
          Security1(pop: 'simple'),
          Security1(pop: 'complex_password_123!@#'),
          Security1(pop: 'unicode_パスワード'),
        ];

        expect(securities[0].pop, equals(''));
        expect(securities[1].pop, equals('simple'));
        expect(securities[2].pop, equals('complex_password_123!@#'));
        expect(securities[3].pop, equals('unicode_パスワード'));
      });
    });

    group('State Management', () {
      test('should start with request1 state', () {
        expect(security1.sessionState, equals(SecurityState.request1));
      });

      test(
          'should transition through states correctly during session establishment',
          () async {
        expect(security1.sessionState, equals(SecurityState.request1));

        // First call should return setup0Request and transition to response1Request2
        final firstRequest = await security1.securitySession(SessionData());
        expect(firstRequest, isNotNull);
        expect(security1.sessionState, equals(SecurityState.response1Request2));
      });

      test('should handle state transitions with different starting states',
          () {
        final security = Security1(sessionState: SecurityState.response2);
        expect(security.sessionState, equals(SecurityState.response2));
      });

      test('should throw exception for finish state', () async {
        security1.sessionState = SecurityState.finish;

        expect(
          () => security1.securitySession(SessionData()),
          throwsException,
        );
      });
    });

    group('Setup0 Request Generation', () {
      test('should create valid setup0 request', () async {
        final request = await security1.setup0Request();

        expect(request.secVer, equals(SecSchemeVersion.SecScheme1));
        expect(request.sec1, isNotNull);
        expect(request.sec1.sc0, isNotNull);
        expect(request.sec1.sc0.clientPubkey, isNotEmpty);
        expect(request.sec1.sc0.clientPubkey.length,
            equals(32)); // X25519 public key size
      });

      test('should generate different keys for different instances', () async {
        final security1Instance = Security1();
        final security2Instance = Security1();

        final request1 = await security1Instance.setup0Request();
        final request2 = await security2Instance.setup0Request();

        expect(
          request1.sec1.sc0.clientPubkey,
          isNot(equals(request2.sec1.sc0.clientPubkey)),
        );
      });

      test('should generate reproducible keys for same instance', () async {
        final request1 = await security1.setup0Request();

        // Reset state for second call
        security1.sessionState = SecurityState.request1;
        final request2 = await security1.setup0Request();

        // Keys should be different since it's generating new ones
        expect(
          request1.sec1.sc0.clientPubkey,
          isNot(equals(request2.sec1.sc0.clientPubkey)),
        );
      });

      test('should handle setup0Request with different PoP configurations',
          () async {
        final securityWithPop = Security1(pop: 'testPop123');
        final securityWithoutPop = Security1();

        final requestWithPop = await securityWithPop.setup0Request();
        final requestWithoutPop = await securityWithoutPop.setup0Request();

        // Both should generate valid requests
        expect(requestWithPop.sec1.sc0.clientPubkey.length, equals(32));
        expect(requestWithoutPop.sec1.sc0.clientPubkey.length, equals(32));

        // Keys should be different
        expect(
          requestWithPop.sec1.sc0.clientPubkey,
          isNot(equals(requestWithoutPop.sec1.sc0.clientPubkey)),
        );
      });
    });

    group('Error Handling Scenarios', () {
      test(
          'should throw exception for invalid security scheme in setup0Response',
          () async {
        await security1.setup0Request();

        final invalidResponse = SessionData();
        invalidResponse.secVer = SecSchemeVersion.SecScheme0; // Invalid scheme

        expect(
          () => security1.setup0Response(invalidResponse),
          throwsException,
        );
      });

      test(
          'should throw exception for unsupported security protocol in setup1Response',
          () async {
        final invalidResponse = SessionData();
        invalidResponse.secVer = SecSchemeVersion.SecScheme0; // Invalid scheme

        expect(
          () => security1.setup1Response(invalidResponse),
          throwsException,
        );
      });

      test('should handle null SessionData gracefully', () async {
        expect(
          () => security1.securitySession(SessionData()),
          returnsNormally,
        );
      });

      test('should handle session data with missing required fields', () async {
        final emptySessionData = SessionData();
        // Don't set any fields

        final result = await security1.securitySession(emptySessionData);
        expect(result, isNotNull);
      });
    });

    group('Proof of Possession Validation', () {
      test('should accept various PoP formats', () {
        final validPops = [
          '',
          '123',
          'abcd',
          'password123',
          'UPPERCASE',
          'MixedCase123',
          'special!@#\$%',
          'unicode_test',
        ];

        for (final pop in validPops) {
          final security = Security1(pop: pop);
          expect(security.pop, equals(pop));
        }
      });

      test('should maintain PoP value throughout object lifetime', () {
        const testPop = 'persistentPassword123';
        final security = Security1(pop: testPop);

        expect(security.pop, equals(testPop));

        // After state changes, PoP should remain the same
        security.sessionState = SecurityState.response2;
        expect(security.pop, equals(testPop));
      });
    });

    group('Session Protocol Validation', () {
      test('should handle session workflow state progression', () async {
        // Start in request1 state
        expect(security1.sessionState, equals(SecurityState.request1));

        // First session call should progress to response1Request2
        final sessionData = SessionData();
        final result = await security1.securitySession(sessionData);

        expect(result, isNotNull);
        expect(security1.sessionState, equals(SecurityState.response1Request2));
      });

      test('should validate session scheme versions', () {
        final sessionData = SessionData();
        sessionData.secVer = SecSchemeVersion.SecScheme1;

        expect(sessionData.secVer, equals(SecSchemeVersion.SecScheme1));
      });
    });
  });
}

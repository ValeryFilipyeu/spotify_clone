import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/validators/email_validator.dart';

void main() {
  group('validateEmail', () {
    test('rejects an empty email', () {
      expect(validateEmail(''), isNotNull);
    });

    test('rejects an email with no @', () {
      expect(validateEmail('not-an-email'), isNotNull);
    });

    test('rejects an email with no domain suffix', () {
      expect(validateEmail('a@b'), isNotNull);
    });

    test('accepts a well-formed email', () {
      expect(validateEmail('test@spotify.com'), isNull);
    });

    test('isValidEmail mirrors validateEmail', () {
      expect(isValidEmail('test@spotify.com'), isTrue);
      expect(isValidEmail(''), isFalse);
    });
  });
}

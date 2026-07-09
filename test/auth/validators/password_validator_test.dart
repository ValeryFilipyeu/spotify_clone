import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/validators/password_validator.dart';

void main() {
  group('validatePassword', () {
    test('rejects an empty password', () {
      expect(validatePassword(''), isNotNull);
    });

    test('rejects a password shorter than 8 characters', () {
      expect(validatePassword('abc123'), isNotNull);
    });

    test('rejects a password with no digit', () {
      expect(validatePassword('abcdefgh'), isNotNull);
    });

    test('accepts a valid password', () {
      expect(validatePassword('Password1'), isNull);
    });

    test('isValidPassword mirrors validatePassword', () {
      expect(isValidPassword('Password1'), isTrue);
      expect(isValidPassword('short'), isFalse);
    });
  });
}

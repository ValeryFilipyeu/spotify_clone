import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/models/app_user.dart';

void main() {
  test('two AppUsers with the same email are equal', () {
    expect(const AppUser('a@b.com'), const AppUser('a@b.com'));
  });

  test('two AppUsers with different emails are not equal', () {
    expect(const AppUser('a@b.com'), isNot(const AppUser('c@d.com')));
  });
}

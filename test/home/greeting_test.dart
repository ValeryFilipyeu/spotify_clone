import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/home/greeting.dart';

DateTime _at(int hour) => DateTime(2026, 8, 4, hour, 30);

void main() {
  group('greetingFor', () {
    test('morning runs from 5am to noon', () {
      expect(greetingFor(_at(5)), 'Good morning');
      expect(greetingFor(_at(9)), 'Good morning');
      expect(greetingFor(_at(11)), 'Good morning');
    });

    test('afternoon runs from noon to 6pm', () {
      expect(greetingFor(_at(12)), 'Good afternoon');
      expect(greetingFor(_at(17)), 'Good afternoon');
    });

    test('evening covers the rest, including the small hours', () {
      expect(greetingFor(_at(18)), 'Good evening');
      expect(greetingFor(_at(23)), 'Good evening');
      expect(greetingFor(_at(2)), 'Good evening');
    });

    // The boundaries are the only interesting part of a rule like this, so they
    // get checked on the minute rather than mid-hour.
    test('changes exactly on the hour', () {
      expect(greetingFor(DateTime(2026, 8, 4, 4, 59)), 'Good evening');
      expect(greetingFor(DateTime(2026, 8, 4, 5)), 'Good morning');
      expect(greetingFor(DateTime(2026, 8, 4, 11, 59)), 'Good morning');
      expect(greetingFor(DateTime(2026, 8, 4, 12)), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 8, 4, 17, 59)), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 8, 4, 18)), 'Good evening');
    });

    test('covers every hour of the day with something', () {
      for (var hour = 0; hour < 24; hour++) {
        expect(greetingFor(_at(hour)), isNotEmpty, reason: 'hour $hour');
      }
    });
  });
}

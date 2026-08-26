import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/likes/models/liked_id.dart';

void main() {
  group('LikedId', () {
    test('the same id in two kinds is two different likes', () {
      // Measured against the live catalog: `aA8xa` is the playlist LATIN
      // ELECTRONIC MUSIC and, separately, the song Reflxt Ride Nb. 08.
      const asPlaylist = LikedId.item('aA8xa');
      const asSong = LikedId.track('aA8xa');

      expect(asPlaylist, isNot(asSong));
      expect({asPlaylist, asSong}, hasLength(2));
      expect({asPlaylist}.contains(asSong), isFalse);
    });

    test('round-trips through its stored form', () {
      for (final liked in [const LikedId.item('aA8xa'), const LikedId.track('dm2-2')]) {
        expect(LikedId.tryParse(liked.encode()), liked);
      }
    });

    test('an id containing a colon survives the round trip', () {
      // Nothing promises catalog ids stay colon-free, and splitting on the last
      // colon instead of the first would quietly truncate the ones that are not.
      const liked = LikedId.track('urn:track:7');

      expect(LikedId.tryParse(liked.encode()), liked);
    });

    test('rejects anything that is not one of ours', () {
      // The middle two are what the untyped version wrote. Parsing them as a
      // kind would be a guess, and a wrong guess is a song in a library that
      // never asked for it.
      for (final input in ['', 'aA8xa', 'dm2-2', 'album:x', ':x', 'item:', 'ITEM:x']) {
        expect(LikedId.tryParse(input), isNull, reason: input);
      }
    });
  });
}

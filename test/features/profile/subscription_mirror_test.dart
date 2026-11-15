import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';

void main() {
  group('ProfileParser.subscriptionMirrorUrl', () {
    test('pixellnet.com subscription goes to the Aeza mirror, path and query kept', () {
      expect(
        ProfileParser.subscriptionMirrorUrl('https://pixellnet.com/sub/abc123/sing-box?x=1'),
        'https://download.pixellnet.com/sub/abc123/sing-box?x=1',
      );
      expect(
        ProfileParser.subscriptionMirrorUrl('https://www.pixellnet.com/sub/abc123'),
        'https://download.pixellnet.com/sub/abc123',
      );
    });

    test('other hosts, paths and plain http are left alone', () {
      expect(ProfileParser.subscriptionMirrorUrl('https://example.com/sub/abc123'), isNull);
      expect(ProfileParser.subscriptionMirrorUrl('https://pixellnet.com/download'), isNull);
      expect(ProfileParser.subscriptionMirrorUrl('http://pixellnet.com/sub/abc123'), isNull);
      expect(ProfileParser.subscriptionMirrorUrl('not a url'), isNull);
    });
  });
}

import 'dart:convert';

import 'package:hiddify/utils/validators.dart';

typedef ProfileLink = ({String url, String name});

// TODO: test and improve
abstract class LinkParser {
  static String generateSubShareLink(String url, [String? name]) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final modifiedUri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      path: uri.path,
      query: uri.query,
      fragment: name ?? uri.fragment,
    );
    // return 'hiddify://import/$modifiedUri';
    return '$modifiedUri';
  }

  // protocols schemas (pixellnet added for share sheet deep links v0.1.44)
  static const protocols = ['pixellnet', 'hiddify', 'v2ray', 'v2rayn', 'v2rayng', 'clash', 'clashmeta', 'sing-box'];

  /// Deep link для нашего PIXELLNET клиента.
  /// Пример: pixellnet://import?url=https://pixellnet.com/sub/TOKEN&name=Pixellnet
  static String generatePixellnetDeepLink(String url, [String? name]) {
    return Uri(
      scheme: 'pixellnet',
      host: 'import',
      queryParameters: {'url': url, if (name != null && name.isNotEmpty) 'name': name},
    ).toString();
  }

  /// Deep link для Hiddify Next (совместим с nekobox, singbox).
  /// Пример: hiddify://import/https://pixellnet.com/sub/TOKEN#Pixellnet
  static String generateHiddifyDeepLink(String url, [String? name]) {
    final fragment = (name != null && name.isNotEmpty) ? '#$name' : '';
    return 'hiddify://import/$url$fragment';
  }

  /// Deep link для Karing (популярный в РФ App Store).
  /// Формат: karing://install-config?url=<enc>&name=<enc>&isp-name=PIXELLNET&isp-url=<enc>
  static String generateKaringDeepLink(String url, [String? name]) {
    return Uri(
      scheme: 'karing',
      host: 'install-config',
      queryParameters: {
        'url': url,
        if (name != null && name.isNotEmpty) 'name': name,
        'isp-name': 'PIXELLNET',
        'isp-url': 'https://pixellnet.com',
      },
    ).toString();
  }

  /// Deep link для V2RayNG (Android).
  /// Формат: v2rayng://install-sub?url=<enc>&name=<enc>
  /// Bug: после импорта юзер должен вручную нажать "Обновить группу" (issue #4141).
  static String generateV2rayNGDeepLink(String url, [String? name]) {
    return Uri(
      scheme: 'v2rayng',
      host: 'install-sub',
      queryParameters: {'url': url, if (name != null && name.isNotEmpty) 'name': name},
    ).toString();
  }

  /// Deep link для Shadowrocket (iOS non-RU App Store).
  /// Формат: sub://<base64(url)>
  static String generateShadowrocketDeepLink(String url) {
    final b64 = base64.encode(utf8.encode(url));
    return 'sub://$b64';
  }

  static ProfileLink? parse(String link) {
    return simple(link) ?? deep(link);
  }

  static ProfileLink? simple(String link) {
    if (!isUrl(link)) return null;
    final uri = Uri.parse(link.trim());
    return (url: uri.toString(), name: uri.queryParameters['name'] ?? '');
  }

  static ProfileLink? deep(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final queryParams = uri.queryParameters;
    switch (uri.scheme) {
      case 'pixellnet' || 'hiddify':
        if (queryParams.containsKey('url')) {
          return (url: queryParams['url']!, name: queryParams['name'] ?? '');
        } else {
          return (url: uri.path.substring(1) + (uri.hasQuery ? "?${uri.query}" : ""), name: uri.fragment);
        }
      case 'v2ray' || 'v2rayn' || 'v2rayng' || 'clash' || 'clashmeta' || 'sing-box':
        return queryParams.containsKey('url') ? (url: queryParams['url']!, name: queryParams['name'] ?? '') : null;
      default:
        return null;
    }
  }
}

String safeDecodeBase64(String str) {
  try {
    return utf8.decode(base64Decode(str));
  } catch (e) {
    return str;
  }
}

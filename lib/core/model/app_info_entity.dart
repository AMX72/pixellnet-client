import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/core/model/environment.dart';

part 'app_info_entity.freezed.dart';

@freezed
class AppInfoEntity with _$AppInfoEntity {
  const AppInfoEntity._();

  const factory AppInfoEntity({
    required String name,
    required String version,
    required String buildNumber,
    required Release release,
    required String operatingSystem,
    required String operatingSystemVersion,
    required Environment environment,
  }) = _AppInfoEntity;

  // 0.1.105 (Р0.7): без «VPN» в подписи. Сервер принимает её с 27.11 (CHANGELOG part 59).
  // «like ClashMeta v2ray sing-box» — служебные слова, по ним сервер выбирает формат подписки.
  String get userAgent => "Pixellnet/$version ($operatingSystem) like ClashMeta v2ray sing-box";

  String get presentVersion => environment == Environment.prod ? version : "$version ${environment.name}";

  /// formats app info for sharing
  String format() =>
      '''
$name v$version ($buildNumber) [${environment.name}]
${release.name} release
$operatingSystem [$operatingSystemVersion]''';
}

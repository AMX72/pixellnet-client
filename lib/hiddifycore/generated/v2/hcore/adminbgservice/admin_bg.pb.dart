// This is a generated file - do not edit.
//
// Generated from v2/hcore/adminbgservice/admin_bg.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class AdminBgStartRequest extends $pb.GeneratedMessage {
  factory AdminBgStartRequest({
    $core.bool? ipv6,
    $core.int? serverPort,
    $core.String? serverUsername,
    $core.String? serverPassword,
    $core.bool? strictRoute,
    $core.bool? endpointIndependentNat,
    $core.String? stack,
    $core.String? configContent,
    $core.String? configName,
    $core.String? settingsJson,
    $core.Iterable<$core.MapEntry<$core.String, $core.List<$core.int>>>?
        resources,
    $core.bool? disableMemoryLimit,
    $core.int? ownerPid,
    $core.bool? proxyOnly,
  }) {
    final result = create();
    if (ipv6 != null) result.ipv6 = ipv6;
    if (serverPort != null) result.serverPort = serverPort;
    if (serverUsername != null) result.serverUsername = serverUsername;
    if (serverPassword != null) result.serverPassword = serverPassword;
    if (strictRoute != null) result.strictRoute = strictRoute;
    if (endpointIndependentNat != null)
      result.endpointIndependentNat = endpointIndependentNat;
    if (stack != null) result.stack = stack;
    if (configContent != null) result.configContent = configContent;
    if (configName != null) result.configName = configName;
    if (settingsJson != null) result.settingsJson = settingsJson;
    if (resources != null) result.resources.addEntries(resources);
    if (disableMemoryLimit != null)
      result.disableMemoryLimit = disableMemoryLimit;
    if (ownerPid != null) result.ownerPid = ownerPid;
    if (proxyOnly != null) result.proxyOnly = proxyOnly;
    return result;
  }

  AdminBgStartRequest._();

  factory AdminBgStartRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AdminBgStartRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AdminBgStartRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'adminbgservice'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ipv6')
    ..aI(2, _omitFieldNames ? '' : 'serverPort')
    ..aOS(3, _omitFieldNames ? '' : 'serverUsername')
    ..aOS(4, _omitFieldNames ? '' : 'serverPassword')
    ..aOB(5, _omitFieldNames ? '' : 'strictRoute')
    ..aOB(6, _omitFieldNames ? '' : 'endpointIndependentNat')
    ..aOS(7, _omitFieldNames ? '' : 'stack')
    ..aOS(8, _omitFieldNames ? '' : 'configContent')
    ..aOS(9, _omitFieldNames ? '' : 'configName')
    ..aOS(10, _omitFieldNames ? '' : 'settingsJson')
    ..m<$core.String, $core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'resources',
        entryClassName: 'AdminBgStartRequest.ResourcesEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OY,
        packageName: const $pb.PackageName('adminbgservice'))
    ..aOB(12, _omitFieldNames ? '' : 'disableMemoryLimit')
    ..aI(13, _omitFieldNames ? '' : 'ownerPid')
    ..aOB(14, _omitFieldNames ? '' : 'proxyOnly')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminBgStartRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminBgStartRequest copyWith(void Function(AdminBgStartRequest) updates) =>
      super.copyWith((message) => updates(message as AdminBgStartRequest))
          as AdminBgStartRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AdminBgStartRequest create() => AdminBgStartRequest._();
  @$core.override
  AdminBgStartRequest createEmptyInstance() => create();
  static $pb.PbList<AdminBgStartRequest> createRepeated() =>
      $pb.PbList<AdminBgStartRequest>();
  @$core.pragma('dart2js:noInline')
  static AdminBgStartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AdminBgStartRequest>(create);
  static AdminBgStartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ipv6 => $_getBF(0);
  @$pb.TagNumber(1)
  set ipv6($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIpv6() => $_has(0);
  @$pb.TagNumber(1)
  void clearIpv6() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get serverPort => $_getIZ(1);
  @$pb.TagNumber(2)
  set serverPort($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerPort() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerPort() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get serverUsername => $_getSZ(2);
  @$pb.TagNumber(3)
  set serverUsername($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasServerUsername() => $_has(2);
  @$pb.TagNumber(3)
  void clearServerUsername() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get serverPassword => $_getSZ(3);
  @$pb.TagNumber(4)
  set serverPassword($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasServerPassword() => $_has(3);
  @$pb.TagNumber(4)
  void clearServerPassword() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get strictRoute => $_getBF(4);
  @$pb.TagNumber(5)
  set strictRoute($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStrictRoute() => $_has(4);
  @$pb.TagNumber(5)
  void clearStrictRoute() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get endpointIndependentNat => $_getBF(5);
  @$pb.TagNumber(6)
  set endpointIndependentNat($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEndpointIndependentNat() => $_has(5);
  @$pb.TagNumber(6)
  void clearEndpointIndependentNat() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get stack => $_getSZ(6);
  @$pb.TagNumber(7)
  set stack($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStack() => $_has(6);
  @$pb.TagNumber(7)
  void clearStack() => $_clearField(7);

  /// Full-core start (macOS root daemon): config snapshot, settings, and local resources.
  @$pb.TagNumber(8)
  $core.String get configContent => $_getSZ(7);
  @$pb.TagNumber(8)
  set configContent($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasConfigContent() => $_has(7);
  @$pb.TagNumber(8)
  void clearConfigContent() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get configName => $_getSZ(8);
  @$pb.TagNumber(9)
  set configName($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasConfigName() => $_has(8);
  @$pb.TagNumber(9)
  void clearConfigName() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get settingsJson => $_getSZ(9);
  @$pb.TagNumber(10)
  set settingsJson($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasSettingsJson() => $_has(9);
  @$pb.TagNumber(10)
  void clearSettingsJson() => $_clearField(10);

  @$pb.TagNumber(11)
  $pb.PbMap<$core.String, $core.List<$core.int>> get resources => $_getMap(10);

  @$pb.TagNumber(12)
  $core.bool get disableMemoryLimit => $_getBF(11);
  @$pb.TagNumber(12)
  set disableMemoryLimit($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasDisableMemoryLimit() => $_has(11);
  @$pb.TagNumber(12)
  void clearDisableMemoryLimit() => $_clearField(12);

  /// When set, the daemon stops once this process is gone (app quit or crash).
  @$pb.TagNumber(13)
  $core.int get ownerPid => $_getIZ(12);
  @$pb.TagNumber(13)
  set ownerPid($core.int value) => $_setSignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasOwnerPid() => $_has(12);
  @$pb.TagNumber(13)
  void clearOwnerPid() => $_clearField(13);

  /// Runs the engine without its TUN (a proxy mode that needs administrator rights).
  @$pb.TagNumber(14)
  $core.bool get proxyOnly => $_getBF(13);
  @$pb.TagNumber(14)
  set proxyOnly($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(14)
  $core.bool hasProxyOnly() => $_has(13);
  @$pb.TagNumber(14)
  void clearProxyOnly() => $_clearField(14);
}

class AdminBgResponse extends $pb.GeneratedMessage {
  factory AdminBgResponse({
    $core.String? message,
    $core.String? systemProxy,
    $core.bool? systemProxySocks,
  }) {
    final result = create();
    if (message != null) result.message = message;
    if (systemProxy != null) result.systemProxy = systemProxy;
    if (systemProxySocks != null) result.systemProxySocks = systemProxySocks;
    return result;
  }

  AdminBgResponse._();

  factory AdminBgResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AdminBgResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AdminBgResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'adminbgservice'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'message')
    ..aOS(2, _omitFieldNames ? '' : 'systemProxy')
    ..aOB(3, _omitFieldNames ? '' : 'systemProxySocks')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminBgResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminBgResponse copyWith(void Function(AdminBgResponse) updates) =>
      super.copyWith((message) => updates(message as AdminBgResponse))
          as AdminBgResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AdminBgResponse create() => AdminBgResponse._();
  @$core.override
  AdminBgResponse createEmptyInstance() => create();
  static $pb.PbList<AdminBgResponse> createRepeated() =>
      $pb.PbList<AdminBgResponse>();
  @$core.pragma('dart2js:noInline')
  static AdminBgResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AdminBgResponse>(create);
  static AdminBgResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get message => $_getSZ(0);
  @$pb.TagNumber(1)
  set message($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);

  /// Where the running engine's system proxy points (host:port), empty when it has none. The
  /// service runs as root and cannot set the user's system proxy: the app's own core sets it.
  @$pb.TagNumber(2)
  $core.String get systemProxy => $_getSZ(1);
  @$pb.TagNumber(2)
  set systemProxy($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSystemProxy() => $_has(1);
  @$pb.TagNumber(2)
  void clearSystemProxy() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get systemProxySocks => $_getBF(2);
  @$pb.TagNumber(3)
  set systemProxySocks($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSystemProxySocks() => $_has(2);
  @$pb.TagNumber(3)
  void clearSystemProxySocks() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');

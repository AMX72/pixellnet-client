// This is a generated file - do not edit.
//
// Generated from v2/hcore/adminbgservice/admin_bg_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import '../../hcommon/common.pb.dart' as $1;
import 'admin_bg.pb.dart' as $0;

export 'admin_bg_service.pb.dart';

/// Elevated background core control API (Windows/Linux OS service, macOS root daemon).
@$pb.GrpcServiceName('adminbgservice.HiddifyAdminBG')
class HiddifyAdminBGClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  HiddifyAdminBGClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.AdminBgResponse> start(
    $0.AdminBgStartRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$start, request, options: options);
  }

  /// Applies a changed configuration to the running engine without restarting it.
  $grpc.ResponseFuture<$0.AdminBgResponse> reload(
    $0.AdminBgStartRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$reload, request, options: options);
  }

  /// Stops the running engine and starts it with the request: a change a reload cannot apply.
  $grpc.ResponseFuture<$0.AdminBgResponse> restart(
    $0.AdminBgStartRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$restart, request, options: options);
  }

  $grpc.ResponseFuture<$0.AdminBgResponse> stop(
    $1.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$stop, request, options: options);
  }

  $grpc.ResponseFuture<$0.AdminBgResponse> status(
    $1.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$status, request, options: options);
  }

  $grpc.ResponseFuture<$0.AdminBgResponse> exit(
    $1.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$exit, request, options: options);
  }

  // method descriptors

  static final _$start =
      $grpc.ClientMethod<$0.AdminBgStartRequest, $0.AdminBgResponse>(
          '/adminbgservice.HiddifyAdminBG/Start',
          ($0.AdminBgStartRequest value) => value.writeToBuffer(),
          $0.AdminBgResponse.fromBuffer);
  static final _$reload =
      $grpc.ClientMethod<$0.AdminBgStartRequest, $0.AdminBgResponse>(
          '/adminbgservice.HiddifyAdminBG/Reload',
          ($0.AdminBgStartRequest value) => value.writeToBuffer(),
          $0.AdminBgResponse.fromBuffer);
  static final _$restart =
      $grpc.ClientMethod<$0.AdminBgStartRequest, $0.AdminBgResponse>(
          '/adminbgservice.HiddifyAdminBG/Restart',
          ($0.AdminBgStartRequest value) => value.writeToBuffer(),
          $0.AdminBgResponse.fromBuffer);
  static final _$stop = $grpc.ClientMethod<$1.Empty, $0.AdminBgResponse>(
      '/adminbgservice.HiddifyAdminBG/Stop',
      ($1.Empty value) => value.writeToBuffer(),
      $0.AdminBgResponse.fromBuffer);
  static final _$status = $grpc.ClientMethod<$1.Empty, $0.AdminBgResponse>(
      '/adminbgservice.HiddifyAdminBG/Status',
      ($1.Empty value) => value.writeToBuffer(),
      $0.AdminBgResponse.fromBuffer);
  static final _$exit = $grpc.ClientMethod<$1.Empty, $0.AdminBgResponse>(
      '/adminbgservice.HiddifyAdminBG/Exit',
      ($1.Empty value) => value.writeToBuffer(),
      $0.AdminBgResponse.fromBuffer);
}

@$pb.GrpcServiceName('adminbgservice.HiddifyAdminBG')
abstract class HiddifyAdminBGServiceBase extends $grpc.Service {
  $core.String get $name => 'adminbgservice.HiddifyAdminBG';

  HiddifyAdminBGServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.AdminBgStartRequest, $0.AdminBgResponse>(
        'Start',
        start_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AdminBgStartRequest.fromBuffer(value),
        ($0.AdminBgResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AdminBgStartRequest, $0.AdminBgResponse>(
        'Reload',
        reload_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AdminBgStartRequest.fromBuffer(value),
        ($0.AdminBgResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AdminBgStartRequest, $0.AdminBgResponse>(
        'Restart',
        restart_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AdminBgStartRequest.fromBuffer(value),
        ($0.AdminBgResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.Empty, $0.AdminBgResponse>(
        'Stop',
        stop_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.Empty.fromBuffer(value),
        ($0.AdminBgResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.Empty, $0.AdminBgResponse>(
        'Status',
        status_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.Empty.fromBuffer(value),
        ($0.AdminBgResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.Empty, $0.AdminBgResponse>(
        'Exit',
        exit_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.Empty.fromBuffer(value),
        ($0.AdminBgResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.AdminBgResponse> start_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AdminBgStartRequest> $request) async {
    return start($call, await $request);
  }

  $async.Future<$0.AdminBgResponse> start(
      $grpc.ServiceCall call, $0.AdminBgStartRequest request);

  $async.Future<$0.AdminBgResponse> reload_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AdminBgStartRequest> $request) async {
    return reload($call, await $request);
  }

  $async.Future<$0.AdminBgResponse> reload(
      $grpc.ServiceCall call, $0.AdminBgStartRequest request);

  $async.Future<$0.AdminBgResponse> restart_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AdminBgStartRequest> $request) async {
    return restart($call, await $request);
  }

  $async.Future<$0.AdminBgResponse> restart(
      $grpc.ServiceCall call, $0.AdminBgStartRequest request);

  $async.Future<$0.AdminBgResponse> stop_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.Empty> $request) async {
    return stop($call, await $request);
  }

  $async.Future<$0.AdminBgResponse> stop(
      $grpc.ServiceCall call, $1.Empty request);

  $async.Future<$0.AdminBgResponse> status_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.Empty> $request) async {
    return status($call, await $request);
  }

  $async.Future<$0.AdminBgResponse> status(
      $grpc.ServiceCall call, $1.Empty request);

  $async.Future<$0.AdminBgResponse> exit_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.Empty> $request) async {
    return exit($call, await $request);
  }

  $async.Future<$0.AdminBgResponse> exit(
      $grpc.ServiceCall call, $1.Empty request);
}

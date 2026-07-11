import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/features/log/model/log_entity.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'logs_overview_state.freezed.dart';

@freezed
class LogsOverviewState with _$LogsOverviewState {
  const LogsOverviewState._();

  const factory LogsOverviewState({
    // v0.1.10 fix: было AsyncLoading — если core не запущен и watchLogs()
    // завершается без yield, UI навсегда висел спиннер. Пустой список =
    // корректный empty state, дальше LogsPage покажет «Пока всё тихо».
    @Default(AsyncData([])) AsyncValue<List<LogEntity>> logs,
    @Default(false) bool paused,
    @Default("") String filter,
    LogLevel? levelFilter,
  }) = _LogsOverviewState;
}

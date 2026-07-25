import '../api/api_models.dart';

enum DataStatus { initial, loading, success, empty, error, offline, unauthorized, forbidden }
class DataState<T> {
  const DataState._(this.status, {this.data, this.failure, this.retry});
  final DataStatus status; final T? data; final ApiFailure? failure; final Future<void> Function()? retry;
  const DataState.initial() : this._(DataStatus.initial);
  const DataState.loading() : this._(DataStatus.loading);
  const DataState.success(T data) : this._(DataStatus.success, data: data);
  const DataState.empty() : this._(DataStatus.empty);
  const DataState.error(ApiFailure failure, {Future<void> Function()? retry}) : this._(DataStatus.error, failure: failure, retry: retry);
  const DataState.offline({T? cachedData, Future<void> Function()? retry}) : this._(DataStatus.offline, data: cachedData, retry: retry);
  const DataState.unauthorized() : this._(DataStatus.unauthorized);
  const DataState.forbidden() : this._(DataStatus.forbidden);
}

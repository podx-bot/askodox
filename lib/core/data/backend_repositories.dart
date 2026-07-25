import '../api/api_models.dart';
abstract interface class UserProfileRepository {Future<ApiResult<Object>> getUser(String id);Future<ApiResult<Object>> saveUser(Object user);}
abstract interface class SellerProfileRepository {Future<ApiResult<Object>> getSeller(String id);Future<ApiResult<Object>> saveSeller(Object seller);}
abstract interface class ProductCatalogDataSource {Future<ApiResult<List<Object>>> products({String? pageToken,int? limit});}
abstract interface class SellerListingsDataSource {Future<ApiResult<List<Object>>> listings(String sellerId,{String? pageToken});}
abstract interface class WatchlistDataSource {Future<ApiResult<List<Object>>> watchlist(String userId);}
abstract interface class AlertsDataSource {Future<ApiResult<List<Object>>> alerts(String userId,{String? pageToken});}
abstract interface class ProductRequestsDataSource {Future<ApiResult<List<Object>>> requests({String? pageToken});}
abstract interface class DemandAnalyticsDataSource {Future<ApiResult<Object>> demand({required String areaId});}
abstract interface class AdminModerationDataSource {Future<ApiResult<List<Object>>> cases({String? pageToken});}
abstract interface class LocationQueryDataSource {Future<ApiResult<List<Object>>> nearby({required double latitude,required double longitude,required double radiusKm,String? pageToken});}

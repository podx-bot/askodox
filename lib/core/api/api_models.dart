enum ApiFailureType { network, timeout, authentication, permission, validation, notFound, duplicate, rateLimit, server, unknown }

class ApiFailure implements Exception {
  const ApiFailure(this.type, {this.message, this.statusCode, this.cause});
  final ApiFailureType type;
  final String? message;
  final int? statusCode;
  final Object? cause;

  String localizedMessage(String languageCode) {
    final te = languageCode == 'te';
    return switch (type) {
      ApiFailureType.network => te ? 'నెట్‌వర్క్ కనెక్షన్‌ను తనిఖీ చేయండి.' : 'Check your network connection.',
      ApiFailureType.timeout => te ? 'అభ్యర్థన సమయం ముగిసింది. మళ్లీ ప్రయత్నించండి.' : 'The request timed out. Try again.',
      ApiFailureType.authentication => te ? 'దయచేసి మళ్లీ సైన్ ఇన్ చేయండి.' : 'Please sign in again.',
      ApiFailureType.permission => te ? 'ఈ చర్యకు మీకు అనుమతి లేదు.' : 'You do not have permission for this action.',
      ApiFailureType.validation => te ? 'నమోదు చేసిన వివరాలను తనిఖీ చేయండి.' : 'Check the information you entered.',
      ApiFailureType.notFound => te ? 'అభ్యర్థించిన అంశం కనుగొనబడలేదు.' : 'The requested item was not found.',
      ApiFailureType.duplicate => te ? 'ఈ అంశం ఇప్పటికే ఉంది.' : 'This item already exists.',
      ApiFailureType.rateLimit => te ? 'చాలా అభ్యర్థనలు. కొద్దిసేపటి తర్వాత ప్రయత్నించండి.' : 'Too many requests. Try again later.',
      ApiFailureType.server => te ? 'సర్వర్ లోపం సంభవించింది.' : 'A server error occurred.',
      ApiFailureType.unknown => te ? 'ఊహించని లోపం సంభవించింది.' : 'An unexpected error occurred.',
    };
  }
}

sealed class ApiResult<T> { const ApiResult(); }
class ApiSuccess<T> extends ApiResult<T> { const ApiSuccess(this.data, {this.nextPageToken}); final T data; final String? nextPageToken; }
class ApiError<T> extends ApiResult<T> { const ApiError(this.failure); final ApiFailure failure; }

ApiFailure mapApiError(Object error, {int? statusCode}) {
  if (error is ApiFailure) return error;
  final type = switch (statusCode) {
    400 => ApiFailureType.validation,
    401 => ApiFailureType.authentication,
    403 => ApiFailureType.permission,
    404 => ApiFailureType.notFound,
    409 => ApiFailureType.duplicate,
    429 => ApiFailureType.rateLimit,
    int code when code >= 500 => ApiFailureType.server,
    _ => ApiFailureType.unknown,
  };
  return ApiFailure(type, statusCode: statusCode, cause: error);
}

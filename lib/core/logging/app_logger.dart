enum LogCategory { appError, authentication, sellerAction, adminAction, syncFailure, apiFailure }
abstract interface class AppLogger { void log(LogCategory category,String event,{Map<String,Object?> context=const{}}); }
class ConsoleAppLogger implements AppLogger {@override void log(LogCategory category,String event,{Map<String,Object?> context=const{}}){final safe=Map<String,Object?>.from(context)..removeWhere((key,value)=>const {'otp','token','document','password','phone','email'}.any((s)=>key.toLowerCase().contains(s)));assert((){print('[${category.name}] $event $safe');return true;}());}}

abstract final class InputSanitizer { static String plainText(String value,{int maxLength=500})=>value.replaceAll(RegExp(r'[<>]'),'').trim().substring(0,value.replaceAll(RegExp(r'[<>]'),'').trim().length.clamp(0,maxLength) as int); }
/// Client checks improve UX only. Backends must validate roles, authorization,
/// rate limits, tokens, inputs, and file type/size/content on every request.
abstract interface class TokenVault { Future<void> save(String token);Future<String?> read();Future<void> clear(); }

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A screen part that fails to build used to show an empty grey / white box in release builds ("Home is blank",
/// owner 2026-11-17). Release builds now show a short message instead, and the error's FIRST line (no personal data:
/// the server masks it and keeps only a signature without consent) goes to the server log `client.build_error`, so the
/// cause can be found without asking the owner for screenshots.
void askodoxInstallBuildErrorView(Uri? apiBase) {
  if (!kReleaseMode) return;
  final sent = <String>{};
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final first = details.exceptionAsString().split('\n').first;
    final where = details.context?.toDescription() ?? '';
    final signature = '$first | $where';
    if (apiBase != null && sent.length < 20 && sent.add(signature)) {
      unawaited(http
          .post(apiBase.resolve('/api/diagnostics/client-error'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'screen': where.length > 80 ? where.substring(0, 80) : where, 'error': first.length > 500 ? first.substring(0, 500) : first}))
          .then((_) {}, onError: (_) {}));
    }
    return const Material(
      color: Color(0xFF382C14),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'ఈ భాగం చూపించలేకపోయాం. వెనక్కి వెళ్ళి మళ్ళీ తెరవండి.\nThis part could not be shown. Go back and open it again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFFFA980), fontSize: 13),
          ),
        ),
      ),
    );
  };
}

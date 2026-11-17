/// A customer's order as STEPS (owner 2026-11-17): every step once, the time it happened in plain words
/// ("సాయంత్రం 7:05"), the step it is waiting on now, and ONE way to pay -- never a step twice, never a raw timestamp.
library;

/// Clock time in the person's words: "ఉదయం 9:05" / "సాయంత్రం 7:05" (Telugu) or "7:05 pm" (English).
/// An earlier day gets its date in front ("16/11 ").
String askodoxClockWords(Object? iso, bool te, {DateTime? now}) {
  final at = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (at == null) return '';
  final today = (now ?? DateTime.now()).toLocal();
  final day = (at.year == today.year && at.month == today.month && at.day == today.day) ? '' : '${at.day}/${at.month} ';
  final h12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final mm = at.minute.toString().padLeft(2, '0');
  if (!te) return '$day$h12:$mm ${at.hour < 12 ? 'am' : 'pm'}';
  final part = at.hour < 4
      ? 'రాత్రి'
      : at.hour < 12
          ? 'ఉదయం'
          : at.hour < 16
              ? 'మధ్యాహ్నం'
              : at.hour < 19
                  ? 'సాయంత్రం'
                  : 'రాత్రి';
  return '$day$part $h12:$mm';
}

/// The name of one step of an order.
String askodoxOrderStepName(String stage, bool te) => switch (stage) {
      'placed' => te ? 'ఆర్డర్ పంపారు' : 'Order sent',
      'accepted' => te ? 'షాప్ ఒప్పుకుంది' : 'Shop accepted',
      'preparing' => te ? 'తయారవుతోంది' : 'Being made',
      'ready' => te ? 'సిద్ధం' : 'Ready',
      'packed' => te ? 'ప్యాక్ చేశారు' : 'Packed',
      'served' => te ? 'టేబుల్‌కి వచ్చింది' : 'Served',
      'handed' => te ? 'మీకు ఇచ్చారు' : 'Handed over',
      'out_for_delivery' => te ? 'దారిలో ఉంది' : 'On the way',
      'delivered' => te ? 'అందింది' : 'Delivered',
      'done' => te ? 'పూర్తయింది' : 'Done',
      'rejected' => te ? 'షాప్ తీసుకోలేదు' : 'Shop could not take it',
      'cancelled' => te ? 'రద్దు చేశారు' : 'Cancelled',
      _ => stage,
    };

enum AskodoxStepState { done, now, next }

class AskodoxOrderStep {
  const AskodoxOrderStep(this.stage, this.at, this.state);
  final String stage;
  final String at; // ISO time it happened ('' = not yet)
  final AskodoxStepState state;
}

/// The order's own lane (`flow` from the server, else the timeline order) with each step's FIRST time.
/// A closed order (rejected / cancelled) ends at that step.
List<AskodoxOrderStep> askodoxOrderSteps(Map<String, Object?> order) {
  final timeline = [for (final t in (order['timeline'] as List? ?? const [])) if (t is Map) t];
  final when = <String, String>{};
  for (final t in timeline) {
    if ('${t['kind'] ?? 'step'}' == 'note') continue;
    when.putIfAbsent('${t['stage']}', () => '${t['at'] ?? ''}');
  }
  var stage = '${order['stage'] ?? ''}';
  if (stage == 'accepting') stage = 'placed';
  if (stage == 'rejected' || stage == 'cancelled') {
    return [
      for (final s in when.keys)
        AskodoxOrderStep(s, when[s]!, AskodoxStepState.done),
    ];
  }
  final flow = [for (final s in (order['flow'] as List? ?? const [])) '$s'];
  final lane = flow.isNotEmpty ? flow : when.keys.toList();
  final here = lane.indexOf(stage);
  return [
    for (var i = 0; i < lane.length; i++)
      if (lane[i] != 'done' || stage == 'done')
        AskodoxOrderStep(
          lane[i],
          when[lane[i]] ?? '',
          i <= here
              ? AskodoxStepState.done
              : i == here + 1
                  ? AskodoxStepState.now
                  : AskodoxStepState.next,
        ),
  ];
}

/// Waiting for the shop to say yes: the customer must not pay yet.
bool askodoxOrderAwaitsShop(Map<String, Object?> order) =>
    const ['placed', 'accepting'].contains('${order['stage'] ?? ''}');

/// ONE way to pay (the first UPI link the shop gave) -- the shop may have several UPI ids; the customer needs one button.
String? askodoxOrderPayLink(Map<String, Object?> order) {
  if (askodoxOrderAwaitsShop(order)) return null;
  for (final p in (order['pay'] as List? ?? const [])) {
    if (p is Map && '${p['upi_link'] ?? ''}'.isNotEmpty) return '${p['upi_link']}';
  }
  return null;
}

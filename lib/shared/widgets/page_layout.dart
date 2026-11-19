import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The person's own page layout (owner 2026-11-19): on hub pages (Tools, Money, Shopping, business pages) each section's
/// buttons can be put in their own order (drag, phone style), renamed, hidden and brought back, and the section heading
/// renamed. Rules:
/// - a button is known by its fixed KEY id; a new name is only a label for this person (guides, chat commands and
///   error reports keep using the key, so support sees both);
/// - nothing is ever deleted -- hide / restore only, and a section never becomes empty by accident (one stays);
/// - buttons added by an app update come at the end of the saved order; buttons that no longer exist are ignored;
/// - "Reset to default" brings the section back as shipped. Saved per account (cleared on sign-out).
const askodoxPageLayoutKey = 'askodox.layout.v1';

class AskodoxSectionLayout {
  const AskodoxSectionLayout({this.title, this.order = const [], this.hidden = const {}, this.names = const {}});

  /// The person's own heading, or null for the shipped one.
  final String? title;
  final List<String> order;
  final Set<String> hidden;

  /// Key id -> the person's own label (display only).
  final Map<String, String> names;

  bool get isDefault => title == null && order.isEmpty && hidden.isEmpty && names.isEmpty;

  Map<String, Object?> toJson() => {
        if (title != null) 'title': title,
        'order': order,
        'hidden': hidden.toList(),
        'names': names,
      };

  static AskodoxSectionLayout fromJson(Object? v) {
    if (v is! Map) return const AskodoxSectionLayout();
    final title = v['title'];
    return AskodoxSectionLayout(
      title: title is String && title.trim().isNotEmpty ? title.trim() : null,
      order: [for (final o in (v['order'] as List? ?? const [])) '$o'],
      hidden: {for (final h in (v['hidden'] as List? ?? const [])) '$h'},
      names: {
        for (final e in ((v['names'] as Map?) ?? const {}).entries)
          if ('${e.value}'.trim().isNotEmpty) '${e.key}': '${e.value}'.trim(),
      },
    );
  }

  AskodoxSectionLayout copyWith({String? title, bool clearTitle = false, List<String>? order, Set<String>? hidden, Map<String, String>? names}) =>
      AskodoxSectionLayout(
        title: clearTitle ? null : (title ?? this.title),
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
        names: names ?? this.names,
      );
}

/// [ids] (the shipped order) arranged by [layout]: saved order first, new ids at the end in shipped order,
/// unknown saved ids dropped. Hidden ids are kept here; callers decide whether to draw them.
List<String> askodoxArrangedIds(List<String> ids, AskodoxSectionLayout layout) {
  final known = ids.toSet();
  final ordered = [for (final id in layout.order) if (known.contains(id)) id];
  final seen = ordered.toSet();
  return [...ordered, for (final id in ids) if (!seen.contains(id)) id];
}

class AskodoxPageLayoutController extends StateNotifier<Map<String, AskodoxSectionLayout>> {
  AskodoxPageLayoutController() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(askodoxPageLayoutKey);
      if (raw == null || !mounted) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      state = {for (final e in data.entries) '${e.key}': AskodoxSectionLayout.fromJson(e.value)};
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          askodoxPageLayoutKey, jsonEncode({for (final e in state.entries) if (!e.value.isDefault) e.key: e.value.toJson()}));
    } catch (_) {}
  }

  AskodoxSectionLayout of(String section) => state[section] ?? const AskodoxSectionLayout();

  void put(String section, AskodoxSectionLayout layout) {
    state = {...state, section: layout};
    _save();
  }

  void reset(String section) {
    state = {for (final e in state.entries) if (e.key != section) e.key: e.value};
    _save();
  }
}

final askodoxPageLayoutProvider = StateNotifierProvider<AskodoxPageLayoutController, Map<String, AskodoxSectionLayout>>(
    (ref) => AskodoxPageLayoutController());

/// One button as the arrange sheet shows it.
class AskodoxLayoutItem {
  const AskodoxLayoutItem({required this.id, required this.title, required this.icon});
  final String id;
  final String title;
  final IconData icon;
}

/// "Arrange this section": drag to reorder (the lifted button grows and the drop place opens, phone style), the eye
/// hides / brings back, the pencil renames; the heading can be renamed; Reset brings the shipped layout back.
Future<void> askodoxArrangeSection(
    BuildContext context, String section, String shippedTitle, List<AskodoxLayoutItem> items) async {
  final container = ProviderScope.containerOf(context);
  final control = container.read(askodoxPageLayoutProvider.notifier);
  final te = Localizations.localeOf(context).languageCode == 'te';
  final byId = {for (final i in items) i.id: i};
  var layout = control.of(section);
  var ids = askodoxArrangedIds([for (final i in items) i.id], layout);

  Future<String?> ask(BuildContext ctx, String label, String current) async {
    final box = TextEditingController(text: current);
    final out = await showDialog<String>(
      context: ctx,
      builder: (dialog) => AlertDialog(
        title: Text(label),
        content: TextField(key: const Key('askodoxLayoutName'), controller: box, autofocus: true, maxLength: 40),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, box.text.trim()), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    // not disposed here: the dialog's closing animation still shows the box
    return out;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(builder: (ctx, setSheet) {
      void save(AskodoxSectionLayout next) {
        layout = next;
        control.put(section, next);
        setSheet(() {});
      }

      final visible = ids.where((id) => !layout.hidden.contains(id)).length;
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .75,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              key: const Key('askodoxLayoutHeading'),
              title: Text(layout.title ?? shippedTitle, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              subtitle: Text(te ? 'పట్టుకుని లాగి క్రమం మార్చండి. 👁 దాచు / చూపు, ✏️ పేరు మార్చు.' : 'Hold and drag to reorder. 👁 hide / show, ✏️ rename.'),
              trailing: IconButton(
                tooltip: te ? 'హెడ్డింగ్ పేరు మార్చు' : 'Rename heading',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final name = await ask(ctx, te ? 'హెడ్డింగ్ పేరు' : 'Heading name', layout.title ?? shippedTitle);
                  if (name == null) return;
                  save(name.isEmpty || name == shippedTitle ? layout.copyWith(clearTitle: true) : layout.copyWith(title: name));
                },
              ),
            ),
            Expanded(
              child: ReorderableListView(
                key: const Key('askodoxLayoutList'),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 1, end: 1.06).animate(animation),
                  child: Material(elevation: 6, borderRadius: BorderRadius.circular(14), child: child),
                ),
                onReorderItem: (from, to) {
                  // the new index is already adjusted for the removed item
                  final list = [...ids];
                  final moved = list.removeAt(from);
                  list.insert(to.clamp(0, list.length), moved);
                  ids = list;
                  save(layout.copyWith(order: list));
                },
                children: [
                  for (final (index, id) in ids.indexed)
                    ReorderableDelayedDragStartListener(
                      key: ValueKey('askodoxLayoutRow-$id'),
                      index: index,
                      child: ListTile(
                        leading: Icon(byId[id]!.icon),
                        title: Text(layout.names[id] ?? byId[id]!.title,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: layout.hidden.contains(id) ? const Color(0xFF9CA3AF) : null,
                                decoration: layout.hidden.contains(id) ? TextDecoration.lineThrough : null)),
                        subtitle: layout.names.containsKey(id) ? Text(byId[id]!.title, style: const TextStyle(fontSize: 11.5)) : null,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            key: ValueKey('askodoxLayoutRename-$id'),
                            tooltip: te ? 'పేరు మార్చు' : 'Rename',
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () async {
                              final name = await ask(ctx, te ? 'బటన్ పేరు' : 'Button name', layout.names[id] ?? byId[id]!.title);
                              if (name == null) return;
                              final names = {...layout.names}..remove(id);
                              if (name.isNotEmpty && name != byId[id]!.title) names[id] = name;
                              save(layout.copyWith(names: names));
                            },
                          ),
                          IconButton(
                            key: ValueKey('askodoxLayoutHide-$id'),
                            tooltip: layout.hidden.contains(id) ? (te ? 'చూపు' : 'Show') : (te ? 'దాచు' : 'Hide'),
                            icon: Icon(layout.hidden.contains(id) ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                            onPressed: () {
                              final hidden = {...layout.hidden};
                              if (hidden.contains(id)) {
                                hidden.remove(id);
                              } else if (visible <= 1) {
                                // never an empty section: the last button stays
                                ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                                    content: Text(te ? 'కనీసం ఒక బటన్ ఉండాలి.' : 'At least one button stays.')));
                                return;
                              } else {
                                hidden.add(id);
                              }
                              save(layout.copyWith(hidden: hidden));
                            },
                          ),
                          const Icon(Icons.drag_indicator, color: Color(0xFF9CA3AF)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: OutlinedButton.icon(
                key: const Key('askodoxLayoutReset'),
                onPressed: () {
                  control.reset(section);
                  layout = const AskodoxSectionLayout();
                  ids = [for (final i in items) i.id];
                  setSheet(() {});
                },
                icon: const Icon(Icons.restart_alt),
                label: Text(te ? 'మొదటి లాగే (డిఫాల్ట్)' : 'Reset to default'),
              ),
            ),
          ]),
        ),
      );
    }),
  );
}

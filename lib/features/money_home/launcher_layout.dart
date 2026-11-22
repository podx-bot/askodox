import 'dart:convert';

/// The person's own phone-style screen of pages (owner 2026-11-22, "Money" in both modes): single pages and FOLDERS
/// (4-5 pages in one box), the person's own folders and names, and as many screens as the pages need (a full screen
/// spills onto the next one, like a phone). Rules:
/// - a page is known by its fixed id; folder names are only the person's labels;
/// - nothing is deleted -- hide / bring back only; a folder left with one page becomes that page again;
/// - pages added by an app update come at the end; pages this phone no longer has are skipped;
/// - "Reset" brings the shipped screen back.
class AskodoxLaunchEntry {
  const AskodoxLaunchEntry.page(String this.page)
      : folder = null,
        name = '',
        children = const [];
  const AskodoxLaunchEntry.folder(String this.folder, this.name, this.children) : page = null;

  /// A single page's id (null for a folder).
  final String? page;

  /// A folder's own id (null for a page).
  final String? folder;
  final String name;
  final List<String> children;

  bool get isFolder => folder != null;

  /// One id for both kinds: the page id, or `f:` + the folder id.
  String get id => isFolder ? 'f:$folder' : page!;

  /// Every page id inside this entry.
  List<String> get pages => isFolder ? children : [page!];

  AskodoxLaunchEntry renamed(String to) => AskodoxLaunchEntry.folder(folder!, to, children);
  AskodoxLaunchEntry withChildren(List<String> kids) => AskodoxLaunchEntry.folder(folder!, name, kids);

  Map<String, Object?> toJson() => isFolder ? {'folder': folder, 'name': name, 'children': children} : {'page': page};

  static AskodoxLaunchEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    if (j['page'] is String && '${j['page']}'.isNotEmpty) return AskodoxLaunchEntry.page('${j['page']}');
    if (j['folder'] is String && '${j['folder']}'.isNotEmpty) {
      final kids = j['children'] is List ? [for (final c in j['children'] as List) '$c'] : <String>[];
      return AskodoxLaunchEntry.folder('${j['folder']}', '${j['name'] ?? ''}', kids);
    }
    return null;
  }

  @override
  String toString() => isFolder ? '[$name: ${children.join(',')}]' : page!;
}

class AskodoxLaunchLayout {
  const AskodoxLaunchLayout(this.entries, {this.hidden = const {}});

  final List<AskodoxLaunchEntry> entries;

  /// Pages the person hid (brought back from "Hidden").
  final Set<String> hidden;

  /// Every page placed on the screens (inside folders too).
  Set<String> get placed => {for (final e in entries) ...e.pages};

  /// Keeps only [available] pages: unknown ones are skipped, a folder with one page left becomes that page, a folder
  /// with none goes, each page appears once, and every available page that is neither placed nor hidden is added at
  /// the end (an app update's new pages). Hidden pages stay hidden.
  AskodoxLaunchLayout fitTo(List<String> available) {
    final ok = available.toSet();
    final seen = <String>{};
    final hid = {for (final h in hidden) if (ok.contains(h)) h};
    final out = <AskodoxLaunchEntry>[];
    for (final e in entries) {
      if (!e.isFolder) {
        final p = e.page!;
        if (ok.contains(p) && !hid.contains(p) && seen.add(p)) out.add(e);
        continue;
      }
      final kids = [for (final c in e.children) if (ok.contains(c) && !hid.contains(c) && seen.add(c)) c];
      if (kids.length >= 2) {
        out.add(e.withChildren(kids));
      } else if (kids.length == 1) {
        out.add(AskodoxLaunchEntry.page(kids.single));
      }
    }
    for (final p in available) {
      if (!seen.contains(p) && !hid.contains(p)) {
        seen.add(p);
        out.add(AskodoxLaunchEntry.page(p));
      }
    }
    return AskodoxLaunchLayout(out, hidden: hid);
  }

  int indexOf(String id) => entries.indexWhere((e) => e.id == id);

  AskodoxLaunchEntry? entry(String id) {
    final i = indexOf(id);
    return i < 0 ? null : entries[i];
  }

  /// The folder holding [page] (null when the page is on its own).
  AskodoxLaunchEntry? folderOf(String page) {
    for (final e in entries) {
      if (e.isFolder && e.children.contains(page)) return e;
    }
    return null;
  }

  /// Moves entry [id] so it ends up at [to] (an index in the list WITHOUT it; clamped).
  AskodoxLaunchLayout move(String id, int to) {
    final i = indexOf(id);
    if (i < 0) return this;
    final list = [...entries];
    final e = list.removeAt(i);
    list.insert(to.clamp(0, list.length), e);
    return AskodoxLaunchLayout(list, hidden: hidden);
  }

  /// Drops page [dragged] onto [target] (phone style): onto a folder = into it; onto a page = a new folder of both,
  /// named [name], where the target was. A folder is never put inside another folder (it is moved next to it).
  AskodoxLaunchLayout combine(String dragged, String target, {required String newFolderId, required String name}) {
    if (dragged == target) return this;
    final d = entry(dragged);
    final t = entry(target);
    if (d == null || t == null) return this;
    if (d.isFolder) return move(dragged, indexOf(target));
    final list = [...entries]..removeWhere((e) => e.id == dragged);
    final ti = list.indexWhere((e) => e.id == target);
    if (t.isFolder) {
      list[ti] = t.withChildren([...t.children, d.page!]);
    } else {
      list[ti] = AskodoxLaunchEntry.folder(newFolderId, name, [t.page!, d.page!]);
    }
    return AskodoxLaunchLayout(list, hidden: hidden);
  }

  /// Takes [page] out of its folder; it lands right after the folder (a folder left with one page dissolves).
  AskodoxLaunchLayout takeOut(String page) {
    final f = folderOf(page);
    if (f == null) return this;
    final list = [...entries];
    final fi = list.indexWhere((e) => e.id == f.id);
    final rest = [for (final c in f.children) if (c != page) c];
    if (rest.length >= 2) {
      list[fi] = f.withChildren(rest);
      list.insert(fi + 1, AskodoxLaunchEntry.page(page));
    } else if (rest.length == 1) {
      list[fi] = AskodoxLaunchEntry.page(rest.single);
      list.insert(fi + 1, AskodoxLaunchEntry.page(page));
    } else {
      list[fi] = AskodoxLaunchEntry.page(page);
    }
    return AskodoxLaunchLayout(list, hidden: hidden);
  }

  /// Puts a page that stands on its own into folder [folderId] (at its end).
  AskodoxLaunchLayout addToFolder(String folderId, String page) {
    final f = entry('f:$folderId');
    if (f == null || f.children.contains(page)) return this;
    var base = this;
    if (folderOf(page) != null) base = takeOut(page);
    final list = [...base.entries]..removeWhere((e) => !e.isFolder && e.page == page);
    final fi = list.indexWhere((e) => e.id == 'f:$folderId');
    if (fi < 0) return this;
    list[fi] = list[fi].withChildren([...list[fi].children, page]);
    return AskodoxLaunchLayout(list, hidden: hidden);
  }

  /// A new folder of [pages] (each taken from where it was), placed where the first of them stood.
  AskodoxLaunchLayout newFolder(List<String> pages, {required String folderId, required String name}) {
    final want = [for (final p in pages) if (placed.contains(p)) p];
    if (want.length < 2) return this;
    var base = this;
    for (final p in want) {
      if (base.folderOf(p) != null) base = base.takeOut(p);
    }
    final at = base.entries.indexWhere((e) => !e.isFolder && want.contains(e.page));
    final list = [...base.entries]..removeWhere((e) => !e.isFolder && want.contains(e.page));
    list.insert(at.clamp(0, list.length), AskodoxLaunchEntry.folder(folderId, name, want));
    return AskodoxLaunchLayout(list, hidden: base.hidden);
  }

  /// Takes every page out of folder [folderId], in its place and order (owner 2026-11-22: folders are only the person's
  /// own; one tap empties one).
  AskodoxLaunchLayout ungroup(String folderId) {
    final out = <AskodoxLaunchEntry>[];
    for (final e in entries) {
      if (e.folder == folderId) {
        out.addAll([for (final c in e.children) AskodoxLaunchEntry.page(c)]);
      } else {
        out.add(e);
      }
    }
    return AskodoxLaunchLayout(out, hidden: hidden);
  }

  /// Folders the app made itself in an earlier version: their pages go back on the screen (user folders stay).
  AskodoxLaunchLayout withoutFolders(Set<String> folderIds) {
    var l = this;
    for (final id in folderIds) {
      if (l.entry('f:$id') != null) l = l.ungroup(id);
    }
    return l;
  }

  /// Moves [page] inside its folder to [to] (an index in the folder's list WITHOUT it). A page from elsewhere is
  /// taken from where it was and put into the folder at [to].
  AskodoxLaunchLayout moveInFolder(String folderId, String page, int to) {
    var base = this;
    final from = base.folderOf(page);
    if (from != null && from.folder != folderId) base = base.takeOut(page);
    if (base.entry('f:$folderId') == null) return this;
    final list = [...base.entries]..removeWhere((e) => !e.isFolder && e.page == page);
    final fi = list.indexWhere((e) => e.id == 'f:$folderId');
    if (fi < 0) return this;
    final kids = [for (final c in list[fi].children) if (c != page) c];
    kids.insert(to.clamp(0, kids.length), page);
    list[fi] = list[fi].withChildren(kids);
    return AskodoxLaunchLayout(list, hidden: base.hidden);
  }

  AskodoxLaunchLayout rename(String folderId, String name) {
    final clean = name.trim();
    if (clean.isEmpty) return this;
    return AskodoxLaunchLayout([for (final e in entries) e.folder == folderId ? e.renamed(clean) : e], hidden: hidden);
  }

  /// Hides [page] (never deleted): it goes to "Hidden" and can be brought back.
  AskodoxLaunchLayout hide(String page) {
    final base = folderOf(page) != null ? takeOut(page) : this;
    return AskodoxLaunchLayout([for (final e in base.entries) if (e.isFolder || e.page != page) e],
        hidden: {...base.hidden, page});
  }

  /// Brings a hidden page back at the end.
  AskodoxLaunchLayout restore(String page) {
    if (!hidden.contains(page)) return this;
    return AskodoxLaunchLayout([...entries, AskodoxLaunchEntry.page(page)], hidden: {...hidden}..remove(page));
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'entries': [for (final e in entries) e.toJson()],
        'hidden': hidden.toList(),
      };

  String encode() => jsonEncode(toJson());

  static AskodoxLaunchLayout? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['entries'] is! List) return null;
      return AskodoxLaunchLayout(
        (j['entries'] as List).map(AskodoxLaunchEntry.fromJson).whereType<AskodoxLaunchEntry>().toList(),
        hidden: j['hidden'] is List ? {for (final h in j['hidden'] as List) '$h'} : <String>{},
      );
    } catch (_) {
      return null;
    }
  }
}

/// Splits [entries] into screens: the first holds [firstSlots] (it also carries the account card), the others
/// [slots]. Never an empty screen; at least one screen.
List<List<AskodoxLaunchEntry>> askodoxLaunchScreens(List<AskodoxLaunchEntry> entries, int firstSlots, int slots) {
  final first = firstSlots < 1 ? 1 : firstSlots;
  final each = slots < 1 ? 1 : slots;
  final out = <List<AskodoxLaunchEntry>>[entries.take(first).toList()];
  var i = first;
  while (i < entries.length) {
    out.add(entries.skip(i).take(each).toList());
    i += each;
  }
  return out;
}

/// Where screen [screen] starts in the entry list.
int askodoxLaunchScreenStart(int screen, int firstSlots, int slots) => screen <= 0 ? 0 : firstSlots + (screen - 1) * slots;

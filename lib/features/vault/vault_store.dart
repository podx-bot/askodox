import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vault_logic.dart';

/// The person's papers, on this phone only (account-scoped, see `askodoxAccountScopedKeys`).
const askodoxVaultPrefsKey = 'askodox.vault.v1';

final askodoxVaultClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Where the photos live: the app's own folder on this phone. Tests swap it for memory.
abstract interface class AskodoxVaultFiles {
  /// Keeps the photo; returns its name ('' when it could not be kept).
  Future<String> save(String id, Uint8List bytes);
  Future<Uint8List?> read(String name);
  Future<void> remove(String name);
}

class AskodoxVaultDeviceFiles implements AskodoxVaultFiles {
  const AskodoxVaultDeviceFiles();

  Future<Directory> _folder() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/askodox_vault');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  @override
  Future<String> save(String id, Uint8List bytes) async {
    try {
      final name = '$id.jpg';
      await File('${(await _folder()).path}/$name').writeAsBytes(bytes, flush: true);
      return name;
    } catch (_) {
      return '';
    }
  }

  @override
  Future<Uint8List?> read(String name) async {
    try {
      if (name.isEmpty || name.contains('/') || name.contains('..')) return null;
      final file = File('${(await _folder()).path}/$name');
      return file.existsSync() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> remove(String name) async {
    try {
      if (name.isEmpty || name.contains('/') || name.contains('..')) return;
      final file = File('${(await _folder()).path}/$name');
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // The record goes anyway; a leftover file is on the person's own phone.
    }
  }
}

final askodoxVaultFilesProvider = Provider<AskodoxVaultFiles>((ref) => const AskodoxVaultDeviceFiles());

class AskodoxVaultState {
  const AskodoxVaultState({this.loaded = false, this.papers = const []});
  final bool loaded;
  final List<AskodoxVaultPaper> papers;
}

class AskodoxVaultController extends StateNotifier<AskodoxVaultState> {
  AskodoxVaultController(this._files) : super(const AskodoxVaultState()) {
    _load();
  }

  final AskodoxVaultFiles _files;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = AskodoxVaultState(loaded: true, papers: askodoxVaultDecode(prefs.getString(askodoxVaultPrefsKey)));
    } catch (_) {
      if (mounted) state = const AskodoxVaultState(loaded: true);
    }
  }

  Future<void> _put(List<AskodoxVaultPaper> papers) async {
    state = AskodoxVaultState(loaded: true, papers: papers);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxVaultPrefsKey, askodoxVaultEncode(papers));
    } catch (_) {
      // Stays on screen; saved with the next change.
    }
  }

  /// A new paper, or the same one again (same id). [photo] is kept on the phone when given.
  Future<AskodoxVaultPaper> save(AskodoxVaultPaper paper, {Uint8List? photo}) async {
    var kept = paper;
    if (photo != null && photo.isNotEmpty) {
      final name = await _files.save(paper.id, photo);
      kept = AskodoxVaultPaper(
          id: paper.id, item: paper.item, shop: paper.shop, boughtOn: paper.boughtOn, warrantyUntil: paper.warrantyUntil,
          serial: paper.serial, servicePhone: paper.servicePhone, amountPaise: paper.amountPaise, photo: name,
          remind: paper.remind, addedAt: paper.addedAt);
    }
    final rest = [for (final p in state.papers) if (p.id != kept.id) p];
    final all = [...rest, kept];
    await _put(all.length > askodoxVaultKeep ? all.sublist(all.length - askodoxVaultKeep) : all);
    return kept;
  }

  Future<void> remove(String id) async {
    for (final p in state.papers) {
      if (p.id == id) await _files.remove(p.photo);
    }
    await _put([for (final p in state.papers) if (p.id != id) p]);
  }
}

final askodoxVaultProvider = StateNotifierProvider<AskodoxVaultController, AskodoxVaultState>(
    (ref) => AskodoxVaultController(ref.watch(askodoxVaultFilesProvider)));

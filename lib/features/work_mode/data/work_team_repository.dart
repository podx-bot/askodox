import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// Work Mode team (owner 2026-11-09): family / friends do one job together,
/// each moved by their own phone's steps. The server shares only the name a
/// person typed for the team, their worker's clothes and their day total.
class AskodoxWorkTeamMember {
  const AskodoxWorkTeamMember({
    required this.member,
    required this.name,
    this.wear = 'lungi',
    this.steps = 0,
    this.active = false,
    this.me = false,
  });

  final String member, name, wear;
  final int steps;

  /// Steps went up in the last few minutes (walking / working now).
  final bool active;
  final bool me;

  factory AskodoxWorkTeamMember.fromJson(Map<String, Object?> j) => AskodoxWorkTeamMember(
        member: '${j['member'] ?? ''}',
        name: '${j['name'] ?? ''}',
        wear: '${j['wear'] ?? 'lungi'}',
        steps: (j['steps'] as num?)?.toInt() ?? 0,
        active: j['active'] == true,
        me: j['me'] == true,
      );
}

class AskodoxWorkTeam {
  const AskodoxWorkTeam({
    required this.code,
    required this.name,
    required this.job,
    this.size = 'medium',
    this.day = '',
    this.maxMembers = 4,
    this.members = const [],
  });

  final String code, name, job, size, day;
  final int maxMembers;
  final List<AskodoxWorkTeamMember> members;

  factory AskodoxWorkTeam.fromJson(Map<String, Object?> j) => AskodoxWorkTeam(
        code: '${j['code'] ?? ''}',
        name: '${j['name'] ?? ''}',
        job: '${j['job'] ?? ''}',
        size: '${j['size'] ?? 'medium'}',
        day: '${j['day'] ?? ''}',
        maxMembers: (j['max_members'] as num?)?.toInt() ?? 4,
        members: [
          for (final m in (j['members'] as List?) ?? const [])
            if (m is Map) AskodoxWorkTeamMember.fromJson(Map<String, Object?>.from(m)),
        ],
      );
}

/// A team call's answer: the team (null = not in one) or a problem code
/// (signin / CODE_NOT_FOUND / TEAM_FULL / ALREADY_IN_TEAM / rate / unavailable).
typedef AskodoxWorkTeamAnswer = ({AskodoxWorkTeam? team, String? problem});

String _code(ApiFailure f) {
  if (f.statusCode == 401) return 'signin';
  if (f.statusCode == 429) return 'rate';
  final m = f.message ?? '';
  for (final c in const ['CODE_NOT_FOUND', 'TEAM_FULL', 'ALREADY_IN_TEAM', 'NAME_REQUIRED']) {
    if (m.contains(c)) return c;
  }
  return 'unavailable';
}

class WorkTeamRepository {
  const WorkTeamRepository(this._client, {this.authToken});
  final ApiClient _client;
  final String? authToken;

  bool get signedIn => authToken != null && authToken!.isNotEmpty;
  ApiRequestOptions get _auth => ApiRequestOptions(authToken: authToken);

  AskodoxWorkTeamAnswer _answer(ApiResult<Map<String, Object?>> result) {
    if (result is ApiError<Map<String, Object?>>) return (team: null, problem: _code(result.failure));
    final t = (result as ApiSuccess<Map<String, Object?>>).data['team'];
    return (team: t is Map ? AskodoxWorkTeam.fromJson(Map<String, Object?>.from(t)) : null, problem: null);
  }

  Future<AskodoxWorkTeamAnswer> mine(String day) async {
    if (!signedIn) return (team: null, problem: 'signin');
    return _answer(await _client.get<Map<String, Object?>>('/api/work/team?day=$day', options: _auth));
  }

  Future<AskodoxWorkTeamAnswer> create(
      {required String name, required String job, required String size, required String wear}) async {
    if (!signedIn) return (team: null, problem: 'signin');
    return _answer(await _client.post<Map<String, Object?>>('/api/work/team',
        body: {'name': name, 'job': job, 'size': size, 'wear': wear}, options: _auth));
  }

  Future<AskodoxWorkTeamAnswer> join({required String code, required String name, required String wear}) async {
    if (!signedIn) return (team: null, problem: 'signin');
    return _answer(await _client.post<Map<String, Object?>>('/api/work/team/join',
        body: {'code': code, 'name': name, 'wear': wear}, options: _auth));
  }

  Future<AskodoxWorkTeamAnswer> reportSteps(String day, int steps) async {
    if (!signedIn) return (team: null, problem: 'signin');
    return _answer(await _client.put<Map<String, Object?>>('/api/work/team/steps',
        body: {'day': day, 'steps': steps}, options: _auth));
  }

  Future<bool> leave() async {
    if (!signedIn) return false;
    final result = await _client.post<Map<String, Object?>>('/api/work/team/leave', body: const {}, options: _auth);
    return result is ApiSuccess<Map<String, Object?>>;
  }
}

final workTeamRepositoryProvider = Provider<WorkTeamRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return WorkTeamRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

class AskodoxWorkTeamState {
  const AskodoxWorkTeamState({this.team, this.problem, this.loaded = false});
  final AskodoxWorkTeam? team;
  final String? problem;
  final bool loaded;
}

/// Keeps the team fresh and sends this phone's day total when it grows
/// (at most once a minute, so the server is not called on every step).
class AskodoxWorkTeamController extends StateNotifier<AskodoxWorkTeamState> {
  AskodoxWorkTeamController(this._repo) : super(const AskodoxWorkTeamState());

  final WorkTeamRepository _repo;
  int _sentSteps = -1;
  String _sentDay = '';
  DateTime? _sentAt;

  bool get signedIn => _repo.signedIn;

  void _apply(AskodoxWorkTeamAnswer a) {
    if (!mounted) return;
    // A passing network problem keeps the team on screen.
    state = AskodoxWorkTeamState(
        team: a.problem == null ? a.team : state.team, problem: a.problem, loaded: true);
  }

  Future<void> refresh(String day) async => _apply(await _repo.mine(day));

  /// Sends today's total when it grew; refreshes the team at the same time.
  Future<void> report(String day, int steps, {bool force = false}) async {
    if (state.team == null) return;
    final now = DateTime.now();
    final recent = _sentAt != null && now.difference(_sentAt!) < const Duration(seconds: 60);
    if (!force && day == _sentDay && (steps <= _sentSteps || recent)) return;
    _sentAt = now;
    _sentDay = day;
    _sentSteps = steps;
    _apply(await _repo.reportSteps(day, steps));
  }

  Future<String?> create({required String name, required String job, required String size, required String wear}) async {
    final a = await _repo.create(name: name, job: job, size: size, wear: wear);
    _apply(a);
    return a.problem;
  }

  Future<String?> join({required String code, required String name, required String wear}) async {
    final a = await _repo.join(code: code, name: name, wear: wear);
    _apply(a);
    return a.problem;
  }

  Future<void> leave() async {
    if (await _repo.leave() && mounted) {
      _sentSteps = -1;
      state = const AskodoxWorkTeamState(loaded: true);
    }
  }
}

final askodoxWorkTeamProvider = StateNotifierProvider<AskodoxWorkTeamController, AskodoxWorkTeamState>(
    (ref) => AskodoxWorkTeamController(ref.watch(workTeamRepositoryProvider)));

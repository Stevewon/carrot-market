import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '../../services/cointrip_service.dart';
import '../../services/qta_service.dart';
import '../../services/rewarded_ad.dart';
import '../../widgets/cointrip_notice.dart';

/// 코인트립 탭 (하단 가운데) — 내 주변에 뿌려진 코인을 지도에서 찾아 줍는다.
///   - 받을 지갑이 없는 코인은 서버가 아예 안 보낸다 → 지갑이 하나도 없으면 안내만.
///   - 가까이(설정값, 처음 300m) 가야 정확한 위치, 멀면 대략적인 동그라미.
///   - 줍기 거리(처음 30m) 안이면 [줍기].
/// [active] 가 false 면 (다른 탭을 보는 중) 위치 추적을 멈춘다.
class CointripTab extends StatefulWidget {
  final bool active;
  const CointripTab({super.key, required this.active});

  /// 위젯 테스트에서는 구글 지도(플랫폼 뷰)를 그릴 수 없어 바꿔 끼운다.
  @visibleForTesting
  static Widget Function(BuildContext context, Set<Marker> markers, Set<Circle> circles, LatLng me)? mapOverride;

  @override
  State<CointripTab> createState() => _CointripTabState();
}

enum _Loc { unknown, serviceOff, denied, ok }

class _CointripTabState extends State<CointripTab> {
  _Loc _loc = _Loc.unknown;
  Position? _me;
  StreamSubscription<Position>? _sub;
  Position? _lastFetchAt;
  DateTime _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;

  List<CtDrop> _drops = const [];
  bool _needWallet = false;
  bool _loading = false;
  String? _error;
  CtDrop? _selected;
  bool _picking = false;
  bool _introAck = false;
  bool _introSending = false;

  GoogleMapController? _map;
  int _radiusM = 5000;

  @override
  void initState() {
    super.initState();
    if (widget.active) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didUpdateWidget(covariant CointripTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
    if (!widget.active && old.active) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<void> _start() async {
    final svc = context.read<CointripService>();
    if (!svc.statusLoaded) await svc.loadStatus();
    if (!mounted || !widget.active) return;
    if (!svc.introAcked) return; // 첫 안내를 먼저 확인
    // 지난번에 정리하지 않은 꽝이 있으면 먼저 (앱을 껐다 켜도 이어서).
    final pending = svc.penalty;
    if (pending != null) await _settleDud(pending);
    final rv = svc.reveal;
    if (rv != null && mounted) await _openReveal(rv);
    if (!mounted || !widget.active) return;
    await _ensureLocation();
  }

  void _stop() {
    _spin?.cancel();
    _spin = null;
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _ensureLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _loc = _Loc.serviceOff);
        return;
      }
      var perm = await Permission.locationWhenInUse.status;
      if (!perm.isGranted) perm = await Permission.locationWhenInUse.request();
      if (!perm.isGranted) {
        if (mounted) setState(() => _loc = _Loc.denied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      if (!mounted) return;
      setState(() {
        _loc = _Loc.ok;
        _me = pos;
      });
      await _fetch(force: true);
      _sub?.cancel();
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen(_onMove, onError: (_) {});
      // 다른 사람이 주워 간 코인을 지우려고 1분마다 다시 받는다.
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _fetch());
    } catch (e) {
      debugPrint('[cointrip] location failed: $e');
      if (mounted) setState(() => _error = context.l10n.ctLocationFailed);
    }
  }

  void _onMove(Position p) {
    if (!mounted) return;
    setState(() => _me = p);
    final last = _lastFetchAt;
    // 50m 넘게 움직이면 다시 받는다 (가까워진 코인의 정확한 위치가 보이게).
    if (last == null || Geolocator.distanceBetween(last.latitude, last.longitude, p.latitude, p.longitude) > 50) {
      _fetch();
    }
  }

  Future<void> _fetch({bool force = false}) async {
    final me = _me;
    if (me == null || _loading) return;
    if (!force && DateTime.now().difference(_lastFetchTime) < const Duration(seconds: 10)) return;
    _loading = true;
    try {
      final r = await context.read<CointripService>().drops(me.latitude, me.longitude, radiusM: _radiusM);
      if (!mounted) return;
      _lastFetchAt = me;
      _lastFetchTime = DateTime.now();
      await _prepareIcons();
      if (!mounted) return;
      setState(() {
        _drops = r.drops;
        _needWallet = r.needWallet;
        _error = null;
        if (_selected != null) {
          _selected = r.drops.where((d) => d.id == _selected!.id).firstOrNull;
        }
      });
      _syncSpin();
    } on CtError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _loading = false;
    }
  }

  // ── 지도 표시: 모든 코인은 사장님이 준 Q 황금 동전이 위아래로 빙글빙글 (블랙코인은 같은 동전을 검게) ──
  // 종류·수량은 주워야 안다 — 비싼 코인만 골라 줍지 않게 (사장님 지시). 서버도 지도에는 안 보낸다.
  static const int _spinFrames = 30; // assets/cointrip/coin_00..29.png (96px)
  static const Duration _spinStep = Duration(milliseconds: 80); // 30장 × 80ms = 2.4초에 한 바퀴 (원본 GIF 와 같게)
  /// 한 번에 도는 코인 수 상한 (지도 마커를 자주 바꾸면 무거워진다). 나머지는 서 있는 그림.
  static const int _maxSpinning = 60;
  static const double _coinSize = 46;
  List<BitmapDescriptor> _gold = const [];
  List<BitmapDescriptor> _black = const [];
  int _frame = 0;
  Timer? _spin;

  Future<void> _prepareIcons() async {
    if (CointripTab.mapOverride != null || _gold.isNotEmpty) return;
    final gold = <BitmapDescriptor>[];
    final black = <BitmapDescriptor>[];
    for (var i = 0; i < _spinFrames; i++) {
      final data = await rootBundle.load('assets/cointrip/coin_${i.toString().padLeft(2, '0')}.png');
      final bytes = data.buffer.asUint8List();
      gold.add(BitmapDescriptor.bytes(bytes, width: _coinSize, height: _coinSize));
      black.add(BitmapDescriptor.bytes(await _darken(bytes), width: _coinSize, height: _coinSize));
    }
    _gold = gold;
    _black = black;
  }

  /// 블랙코인 — 같은 Q 동전을 검게 (반짝임은 조금 남긴다).
  static Future<Uint8List> _darken(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final img = (await codec.getNextFrame()).image;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImage(
      img,
      Offset.zero,
      Paint()
        ..colorFilter = const ColorFilter.matrix(<double>[
          0.12, 0.12, 0.12, 0, 0, //
          0.12, 0.12, 0.12, 0, 0, //
          0.12, 0.12, 0.12, 0, 0, //
          0, 0, 0, 1, 0,
        ]),
    );
    final out = await rec.endRecording().toImage(img.width, img.height);
    final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  void _syncSpin() {
    final want = widget.active && _drops.any((d) => d.precise) && CointripTab.mapOverride == null;
    if (want && _spin == null) {
      _spin = Timer.periodic(_spinStep, (_) {
        if (mounted) setState(() => _frame = (_frame + 1) % _spinFrames);
      });
    } else if (!want) {
      _spin?.cancel();
      _spin = null;
    }
  }

  Set<Marker> _markers() {
    final precise = _drops.where((d) => d.precise).toList();
    return {
      for (var i = 0; i < precise.length; i++)
        Marker(
          markerId: MarkerId(precise[i].id),
          position: LatLng(precise[i].lat, precise[i].lng),
          icon: _iconFor(precise[i], i),
          anchor: const Offset(0.5, 0.5),
          onTap: () => setState(() => _selected = precise[i]),
        ),
    };
  }

  BitmapDescriptor _iconFor(CtDrop d, int i) {
    final frames = d.isBlack ? _black : _gold;
    if (frames.isEmpty) return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    // 코인마다 도는 시점을 조금씩 어긋나게 (한꺼번에 똑같이 돌지 않게).
    return i < _maxSpinning ? frames[(_frame + i * 7) % frames.length] : frames[0];
  }

  Set<Circle> _circles() {
    // 멀리 있는 코인은 같은 칸끼리 하나의 황금빛 동그라미로 (블랙코인은 검은빛).
    final seen = <String>{};
    final out = <Circle>{};
    for (final d in _drops.where((d) => !d.precise)) {
      final color = d.isBlack ? const Color(0xFF222222) : const Color(0xFFF2B705);
      final k = '${d.lat.toStringAsFixed(5)},${d.lng.toStringAsFixed(5)},${d.isBlack}';
      if (!seen.add(k)) continue;
      out.add(Circle(
        circleId: CircleId(k),
        center: LatLng(d.lat, d.lng),
        radius: 280,
        fillColor: color.withValues(alpha: 0.22),
        strokeColor: color.withValues(alpha: 0.75),
        strokeWidth: 2,
        consumeTapEvents: true,
        onTap: () => setState(() => _selected = d),
      ));
    }
    return out;
  }

  double _myDistance(CtDrop d) {
    final me = _me;
    if (me == null) return double.infinity;
    return Geolocator.distanceBetween(me.latitude, me.longitude, d.lat, d.lng);
  }

  void _onCameraIdle() async {
    final m = _map;
    final me = _me;
    if (m == null || me == null) return;
    try {
      final b = await m.getVisibleRegion();
      // 보이는 지도의 끝까지 (최대 20km) — 내 위치 기준으로 받는다.
      final corners = [b.northeast, b.southwest, LatLng(b.northeast.latitude, b.southwest.longitude), LatLng(b.southwest.latitude, b.northeast.longitude)];
      final far = corners
          .map((p) => Geolocator.distanceBetween(me.latitude, me.longitude, p.latitude, p.longitude))
          .reduce(math.max);
      final want = far.clamp(1000, 20000).round();
      if (want > _radiusM * 1.3 || want < _radiusM / 2) {
        _radiusM = want;
        _fetch(force: true);
      }
    } catch (_) {}
  }

  // ── 줍기 ───────────────────────────────────────────────────────────
  Future<void> _pick(CtDrop d) async {
    if (_picking) return;
    final svc = context.read<CointripService>();
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (!svc.phoneVerified) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.ctPhoneRequired),
        action: SnackBarAction(label: l10n.ctVerifyPhone, onPressed: () => context.push('/profile/verify')),
      ));
      return;
    }
    setState(() => _picking = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 10)),
      );
      if (pos.isMocked) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.ctMockedLocation)));
        return;
      }
      final r = await svc.pick(d, lat: pos.latitude, lng: pos.longitude, accuracy: pos.accuracy, mocked: pos.isMocked);
      if (!mounted) return;
      setState(() {
        _drops = _drops.where((x) => x.id != d.id).toList();
        _selected = null;
      });
      if (r.dud != null) {
        await _settleDud(r.dud!);
      } else if (r.reveal != null) {
        await _openReveal(r.reveal!);
      } else if (r.empty) {
        await showDialog<void>(context: context, builder: (_) => const _EmptyDialog());
      } else {
        await showDialog<void>(context: context, builder: (_) => _PickedDialog(result: r));
      }
      _fetch(force: true);
    } on CtError catch (e) {
      if (e.code == 'dud_pending' && e.penalty != null) {
        await _settleDud(e.penalty!);
        return;
      }
      if (e.code == 'reveal_pending' && e.reveal != null) {
        await _openReveal(e.reveal!);
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (e.code == 'gone') {
        setState(() {
          _drops = _drops.where((x) => x.id != d.id).toList();
          _selected = null;
        });
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ctLocationFailed)));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// 블랙코인 꽝 — 광고를 보거나 QTA 를 낼 때까지 닫히지 않는다.
  bool _dudOpen = false;
  Future<void> _settleDud(CtPenalty p) async {
    if (_dudOpen || !mounted) return;
    _dudOpen = true;
    final msg = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: _DudDialog(penalty: p)),
    );
    _dudOpen = false;
    if (!mounted) return;
    // ignore: discarded_futures
    context.read<QtaService>().load(force: true);
    if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 블랙코인 광고 보고 열기 — 광고를 끝까지 보면 코인이 보이고 받는다. 그만두면 지도에 다시 놓인다.
  Future<void> _openReveal(CtReveal rv) async {
    if (_dudOpen || !mounted) return;
    _dudOpen = true;
    final got = await showDialog<CtPickResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: _RevealDialog(reveal: rv)),
    );
    _dudOpen = false;
    if (!mounted) return;
    if (got != null) await showDialog<void>(context: context, builder: (_) => _PickedDialog(result: got));
    _fetch(force: true);
  }

  Future<void> _ackIntro() async {
    setState(() => _introSending = true);
    try {
      await context.read<CointripService>().ack('cointrip_intro');
      if (!mounted) return;
      _start();
    } on CtError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _introSending = false);
    }
  }

  // ── 화면 ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final svc = context.watch<CointripService>();
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(l10n.ctTitle),
        actions: [
          if (svc.introAcked) ...[
            IconButton(
              tooltip: l10n.ctUnion,
              icon: const Icon(Icons.groups_outlined),
              onPressed: () => context.push('/cointrip/union'),
            ),
            IconButton(
              tooltip: l10n.ctMyWallet,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              onPressed: () => context.push('/cointrip/wallet'),
            ),
          ],
        ],
      ),
      body: !svc.statusLoaded
          ? const Center(child: CircularProgressIndicator())
          : !svc.introAcked
              ? _intro(svc)
              : _body(svc),
    );
  }

  Widget _intro(CointripService svc) {
    final l10n = context.l10n;
    final mult = _fmtTimes(svc.finderMultiplier);
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: EggplantColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.45))),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(l10n.ctIntroTitle, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        line(Icons.map_outlined, l10n.ctIntroFind),
        line(Icons.near_me_outlined, l10n.ctIntroPick(svc.pickRadiusM)),
        line(Icons.help_outline_rounded, l10n.ctIntroBlack(svc.dudPenaltyQta)),
        line(Icons.groups_outlined, l10n.ctIntroUnion(mult)),
        line(Icons.account_balance_wallet_outlined, l10n.ctIntroWallet),
        line(Icons.directions_walk_rounded, l10n.ctIntroSafety),
        const SizedBox(height: 6),
        WalletResponsibilityAck(value: _introAck, onChanged: (v) => setState(() => _introAck = v)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _introAck && !_introSending ? _ackIntro : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(l10n.ctAckButton, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _message(IconData icon, String title, String body, {List<Widget> actions = const []}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      children: [
        Icon(icon, size: 56, color: EggplantColors.primary),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: EggplantColors.textSecondary, height: 1.45)),
        const SizedBox(height: 20),
        ...actions,
      ],
    );
  }

  Widget _body(CointripService svc) {
    final l10n = context.l10n;
    if (!svc.hasAnyWallet || _needWallet) {
      return _message(
        Icons.account_balance_wallet_outlined,
        l10n.ctNeedWalletTitle,
        l10n.ctNeedWalletBody,
        actions: [
          FilledButton(
            onPressed: () => context.push('/cointrip/wallet'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(l10n.ctRegisterWallet),
          ),
        ],
      );
    }
    switch (_loc) {
      case _Loc.serviceOff:
      case _Loc.denied:
        return _message(
          Icons.location_off_outlined,
          _loc == _Loc.serviceOff ? l10n.ctLocationServiceOff : l10n.ctLocationNeeded,
          l10n.ctLocationWhy,
          actions: [
            FilledButton(
              onPressed: _ensureLocation,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: Text(l10n.ctRetry),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _loc == _Loc.serviceOff ? Geolocator.openLocationSettings() : openAppSettings(),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: Text(l10n.ctOpenSettings),
            ),
          ],
        );
      case _Loc.unknown:
        if (_error != null) {
          return _message(Icons.error_outline, _error!, '', actions: [
            FilledButton(onPressed: _ensureLocation, child: Text(l10n.ctRetry)),
          ]);
        }
        return const Center(child: CircularProgressIndicator());
      case _Loc.ok:
        break;
    }
    final me = _me!;
    final meLatLng = LatLng(me.latitude, me.longitude);
    final markers = _markers();
    final circles = _circles();
    final map = CointripTab.mapOverride?.call(context, markers, circles, meLatLng) ??
        GoogleMap(
          initialCameraPosition: CameraPosition(target: meLatLng, zoom: 16),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: true,
          markers: markers,
          circles: circles,
          onMapCreated: (c) => _map = c,
          onCameraIdle: _onCameraIdle,
          onTap: (_) => setState(() => _selected = null),
        );
    final nearest = _drops.where((d) => d.precise).fold<CtDrop?>(
        null, (a, d) => a == null || _myDistance(d) < _myDistance(a) ? d : a);
    final shown = _selected ?? nearest;
    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          left: 12,
          top: 12,
          child: _Pill(
            text: _drops.isEmpty ? l10n.ctNoCoinsShort : l10n.ctNearby(_drops.length),
            loading: _loading,
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: shown == null
              ? (_drops.isEmpty ? _Card(child: Text(l10n.ctNoCoinsNearby, style: const TextStyle(fontSize: 14, height: 1.4))) : const SizedBox.shrink())
              : _DropCard(
                  drop: shown,
                  distanceM: shown.precise ? _myDistance(shown) : shown.distanceM.toDouble(),
                  pickRadiusM: svc.pickRadiusM,
                  preciseRadiusM: svc.preciseRadiusM,
                  dudQta: svc.dudPenaltyQta,
                  picking: _picking,
                  onPick: () => _pick(shown),
                  onClose: _selected == null ? null : () => setState(() => _selected = null),
                ),
        ),
      ],
    );
  }
}

String _fmtTimes(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String _fmtDistance(BuildContext context, double m) {
  if (m >= 1000) return context.l10n.ctDistanceKm((m / 1000).toStringAsFixed(1));
  return context.l10n.ctDistanceM(m.round());
}

class _Pill extends StatelessWidget {
  final String text;
  final bool loading;
  const _Pill({required this.text, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.toll_rounded, size: 18, color: EggplantColors.primary),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          if (loading) ...[
            const SizedBox(width: 8),
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}

class _DropCard extends StatelessWidget {
  final CtDrop drop;
  final double distanceM;
  final int pickRadiusM;
  final int preciseRadiusM;
  final int dudQta;
  final bool picking;
  final VoidCallback onPick;
  final VoidCallback? onClose;
  const _DropCard({
    required this.drop,
    required this.distanceM,
    required this.pickRadiusM,
    required this.preciseRadiusM,
    required this.dudQta,
    required this.picking,
    required this.onPick,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canPick = drop.precise && distanceM <= pickRadiusM;
    // 종류·수량은 주워야 안다 — 카드에도 보이지 않는다.
    final title = drop.isBlack ? l10n.ctBlackCoin : l10n.ctGoldCoin;
    final sub = drop.isBlack ? l10n.ctBlackCoinHint(dudQta) : l10n.ctGoldCoinHint;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CoinBadge(black: drop.isBlack, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(title, maxLines: 1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 2),
                    Text(sub, maxLines: 5, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                drop.precise ? _fmtDistance(context, distanceM) : '~${_fmtDistance(context, distanceM)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: EggplantColors.primary),
              ),
              if (onClose != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onClose,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!drop.precise)
            Text(l10n.ctApprox(preciseRadiusM), style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary, height: 1.4))
          else
            FilledButton.icon(
              onPressed: canPick && !picking ? onPick : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: picking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.pan_tool_alt_outlined),
              label: Text(
                canPick ? l10n.ctPick : l10n.ctGetCloser(pickRadiusM),
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _PickedDialog extends StatelessWidget {
  final CtPickResult result;
  const _PickedDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = result;
    return AlertDialog(
      title: Text(r.wasBlack ? l10n.ctBlackOpened : l10n.ctPickedTitle, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Color(r.coin.argb), shape: BoxShape.circle),
            child: Text(
              r.coin.symbol.length > 4 ? r.coin.symbol.substring(0, 4) : r.coin.symbol,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${r.mine} ${r.coin.symbol}', maxLines: 1, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ),
          Text(r.coin.name, style: const TextStyle(color: EggplantColors.textSecondary)),
          if (r.shared.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(l10n.ctSharedWith(r.total, r.coin.symbol), textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final (nick, amt) in r.shared.take(8))
              Row(
                children: [
                  Expanded(
                    child: Text(nick, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  Text('$amt ${r.coin.symbol}', style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary)),
                ],
              ),
            if (r.shared.length > 8)
              Text(l10n.ctSharedMore(r.shared.length - 8), style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary)),
          ],
          const SizedBox(height: 12),
          Text(l10n.ctToWallet, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonConfirm)),
      ],
    );
  }
}

/// Q 황금 동전 그림 (블랙코인은 같은 동전을 검게) — 카드·안내에 쓰는 작은 그림.
class CoinBadge extends StatelessWidget {
  final bool black;
  final double size;
  const CoinBadge({super.key, required this.black, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final img = Image.asset('assets/cointrip/coin_00.png', width: size, height: size, filterQuality: FilterQuality.medium);
    if (!black) return img;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.12, 0.12, 0.12, 0, 0, //
        0.12, 0.12, 0.12, 0, 0, //
        0.12, 0.12, 0.12, 0, 0, //
        0, 0, 0, 1, 0,
      ]),
      child: img,
    );
  }
}

/// 꽝 — [광고 보기] 끝까지 보면 그냥 넘어가고, [QTA 내기] 를 누르면 갖고 있는 QTA 에서 낸다.
/// 정리되면 닫히며 알림 문구를 돌려준다.
class _DudDialog extends StatefulWidget {
  final CtPenalty penalty;
  const _DudDialog({required this.penalty});

  @override
  State<_DudDialog> createState() => _DudDialogState();
}

class _DudDialogState extends State<_DudDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _watch() async {
    final l10n = context.l10n;
    final svc = context.read<CointripService>();
    final uid = context.read<AuthService>().user?.id ?? '';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final earned = await RewardedAds.show(widget.penalty.adUnit, userId: uid, customData: widget.penalty.id);
      if (!mounted) return;
      if (!earned) {
        setState(() => _error = l10n.ctDudAdNotFinished);
        return;
      }
      if (await svc.penaltyAdWatched(widget.penalty)) {
        if (mounted) Navigator.pop(context, l10n.ctDudAdOk);
      } else if (mounted) {
        setState(() => _error = l10n.ctDudAdChecking);
      }
    } on RewardedAdUnavailable {
      if (mounted) setState(() => _error = l10n.ctDudAdFailed);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.ctDudAdFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await context.read<CointripService>().penaltyPay(widget.penalty);
      if (mounted) Navigator.pop(context, l10n.ctDudPaid(n));
    } on CtError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final qta = widget.penalty.qta;
    return AlertDialog(
      title: Text(l10n.ctDudTitle, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CoinBadge(black: true, size: 64),
          const SizedBox(height: 14),
          Text(l10n.ctDudBody(qta), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.45)),
          const SizedBox(height: 6),
          Text(l10n.ctDudDeadline, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: EggplantColors.textSecondary)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: EggplantColors.error, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _watch,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_circle_outline),
            label: Text(l10n.ctDudWatchAd, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _pay,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: EggplantColors.error),
            child: Text(l10n.ctDudPay(qta), textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

/// 블랙코인 꽝 — 아무것도 없다 (내는 것도 없음).
class _EmptyDialog extends StatelessWidget {
  const _EmptyDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.ctEmptyTitle, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CoinBadge(black: true, size: 64),
          const SizedBox(height: 14),
          Text(l10n.ctEmptyBody, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.45)),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonConfirm))],
    );
  }
}

/// 광고 보고 열기 — [광고 보고 열기] 끝까지 보면 코인 결과로 닫히고, [그만두기] 면 null (코인은 지도로).
class _RevealDialog extends StatefulWidget {
  final CtReveal reveal;
  const _RevealDialog({required this.reveal});

  @override
  State<_RevealDialog> createState() => _RevealDialogState();
}

class _RevealDialogState extends State<_RevealDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _watch() async {
    final l10n = context.l10n;
    final svc = context.read<CointripService>();
    final uid = context.read<AuthService>().user?.id ?? '';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final earned = await RewardedAds.show(widget.reveal.adUnit, userId: uid, customData: widget.reveal.id);
      if (!mounted) return;
      if (!earned) {
        setState(() => _error = l10n.ctDudAdNotFinished);
        return;
      }
      final got = await svc.revealAdWatched(widget.reveal);
      if (!mounted) return;
      if (got != null) {
        Navigator.pop(context, got);
      } else {
        setState(() => _error = l10n.ctDudAdChecking);
      }
    } on CtError catch (e) {
      if (mounted) {
        if (e.code == 'settled' || e.code == 'gone') {
          Navigator.pop(context);
        } else {
          setState(() => _error = e.message);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = l10n.ctDudAdFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _giveUp() async {
    setState(() => _busy = true);
    await context.read<CointripService>().revealGiveUp(widget.reveal);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.ctRevealTitle, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CoinBadge(black: true, size: 64),
          const SizedBox(height: 14),
          Text(l10n.ctRevealBody, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.45)),
          const SizedBox(height: 6),
          Text(l10n.ctRevealDeadline, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: EggplantColors.textSecondary)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: EggplantColors.error, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _watch,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_circle_outline),
            label: Text(l10n.ctRevealWatch, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _giveUp,
            child: Text(l10n.ctRevealGiveUp, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

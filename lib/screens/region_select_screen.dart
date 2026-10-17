import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/market.dart';
import '../app/regions.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';

class RegionSelectScreen extends StatefulWidget {
  const RegionSelectScreen({super.key});

  @override
  State<RegionSelectScreen> createState() => _RegionSelectScreenState();
}

class _RegionSelectScreenState extends State<RegionSelectScreen> {
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';
  bool _verifying = false;

  /// 2단계 선택(일본 都道府県 / 필리핀 Province)에서 고른 상위 지역. null 이면 상위 지역 목록 단계.
  String? _pref;

  /// 고르는 중인 내 동네 — 확인을 눌러야 서버에 저장된다 (한 곳 누를 때마다 저장·이동하지 않게).
  List<String> _sel = const [];
  String? _active;
  bool _loaded = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final user = context.read<AuthService>().user;
    if (user == null) return;
    _loaded = true;
    _sel = [...user.regions];
    if (_sel.isEmpty && user.region != null) _sel = [user.region!];
    _active = user.region;
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String get _market => AppMarket.of(context.read<AuthService>().user);

  bool get _isPh => AppMarket.isPh(_market);

  /// 일본·필리핀은 2단계 (상위 지역 → 시·군), 한국은 한 목록.
  bool get _isTwoStep => AppMarket.isJp(_market) || _isPh;

  /// 2단계 상위 지역 — 일본 都道府県 / 필리핀 Province.
  List<String> get _groups =>
      _isPh ? AppRegions.phProvinces : AppRegions.jpPrefectures;

  /// 상위 지역의 시·군 — (전체 이름, 짧은 이름, 읽기 가타카나; 필리핀은 '').
  List<(String, String, String)> _cities(String group) => _isPh
      ? [for (final c in AppRegions.phCities(group)) (c.$1, c.$2, '')]
      : AppRegions.jpCities(group);

  String? _groupOf(String region) =>
      _isPh ? AppRegions.phProvinceOf(region) : AppRegions.jpPrefectureOf(region);

  /// 내 시장(한국/일본/필리핀) 동네만 — 일본어 사용자에게는 일본 지역만 보인다.
  List<String> get _regions => AppRegions.forMarket(_market);

  List<String> get _filtered {
    if (_query.isEmpty) return _regions;
    return _regions
        .where((r) => r.toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  /// 검색어 정규화 — 소문자, 공백·'.'·'-'·''' 제거, ñ → n ('paranaque' 로 Parañaque),
  /// ひらがな → カタカナ (읽기 가나로도 찾게).
  static String _norm(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      if (r == 0x20 || r == 0x3000 || r == 0x2E || r == 0x2D || r == 0x27) continue;
      b.writeCharCode(r >= 0x3041 && r <= 0x3096
          ? r + 0x60
          : r == 0xF1
              ? 0x6E
              : r);
    }
    return b.toString();
  }

  static bool _hit(String q, String name, String kana) =>
      _norm(name).contains(q) || (kana.isNotEmpty && kana.contains(q));

  void _setPref(String? pref) {
    _searchCtl.clear();
    setState(() {
      _pref = pref;
      _query = '';
    });
  }

  /// 동네 인증: GPS 좌표를 받아 서버에 검증 요청.
  /// 정확한 좌표는 서버에서 즉시 폐기되고 region 중심점만 저장된다.
  Future<void> _verifyWithGps({String? region}) async {
    if (_verifying) return;
    setState(() => _verifying = true);

    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    try {
      // 1) 위치 서비스(시스템 GPS) 켜져 있는지.
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.homeLocationServiceOff),
        ));
        return;
      }

      // 2) 권한.
      var perm = await Permission.locationWhenInUse.status;
      if (!perm.isGranted) {
        perm = await Permission.locationWhenInUse.request();
      }
      if (!perm.isGranted) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.homeLocationPermissionNeeded),
        ));
        return;
      }

      // 3) 좌표 획득.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      // 4) 서버 검증. 정확한 좌표는 응답 직후 폐기됨.
      final err = await auth.verifyRegion(
        lat: pos.latitude,
        lng: pos.longitude,
        region: region,
      );

      if (!mounted) return;
      if (err == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.homeRegionVerifiedToast(auth.user?.region ?? l10n.homeMyRegion)),
          backgroundColor: EggplantColors.primary,
        ));
        if (Navigator.canPop(context)) context.pop();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.homeLocationFailed)));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Widget _buildVerifiedBanner(AuthService auth) {
    final verified = auth.user?.isRegionVerified ?? false;
    final region = auth.user?.region;
    if (region == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: verified
            ? EggplantColors.primary.withValues(alpha: 0.08)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: verified
              ? EggplantColors.primary.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            verified ? Icons.verified : Icons.location_off,
            color: verified ? EggplantColors.primary : Colors.orange,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verified ? context.l10n.homeRegionVerified : context.l10n.homeRegionVerifyNeeded,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color:
                        verified ? EggplantColors.primary : Colors.orange[800],
                  ),
                ),
                Text(
                  verified
                      ? context.l10n.homeRegionVerifiedDesc(region)
                      : context.l10n.homeRegionVerifyDesc(region),
                  style: const TextStyle(
                    fontSize: 12,
                    color: EggplantColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _verifying ? null : () => _verifyWithGps(),
            child: _verifying
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(verified ? context.l10n.homeReverify : context.l10n.homeVerify,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  static const int _maxRegions = 10;

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  /// 동네 누르기 — 고른 목록에 있으면 빼고, 없으면 넣는다 (최대 10곳). 저장은 아래 확인 버튼에서 한 번에.
  void _pick(String r) {
    if (_sel.contains(r)) {
      if (_sel.length <= 1) {
        _toast(context.l10n.regionKeepOne);
        return;
      }
      setState(() {
        _sel = [..._sel]..remove(r);
        if (_active == r) _active = _sel.first;
      });
      return;
    }
    if (_sel.length >= _maxRegions) {
      _toast(context.l10n.homeMaxRegions(_maxRegions));
      return;
    }
    setState(() {
      _sel = [..._sel, r];
      _active ??= r;
    });
  }

  /// 확인 — 고른 동네를 한 번에 저장하고 화면을 닫는다.
  Future<void> _confirm(AuthService auth) async {
    if (_saving || _sel.isEmpty) return;
    setState(() => _saving = true);
    final active = _sel.contains(_active) ? _active : _sel.first;
    final err = await auth.setRegions(_sel, active: active);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      _toast(err);
      return;
    }
    if (Navigator.canPop(context)) context.pop();
  }

  Widget _confirmBar(AuthService auth) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _saving || _sel.isEmpty ? null : () => _confirm(auth),
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.l10n.regionConfirm(_sel.length, _maxRegions),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      );

  /// 위쪽 "내 동네 n/10" — 누르면 그 동네를 기본으로, ✕ 로 뺀다.
  Widget _myRegions() {
    final mine = _sel;
    if (mine.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.homeMyRegionsTitle(mine.length, _maxRegions),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(context.l10n.regionMultiHint(_maxRegions),
              style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in mine)
                InputChip(
                  label: Text(r),
                  selected: r == _active,
                  showCheckmark: false,
                  selectedColor: EggplantColors.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    fontWeight: r == _active ? FontWeight.w800 : FontWeight.w500,
                    color: r == _active ? EggplantColors.primary : EggplantColors.textPrimary,
                  ),
                  onPressed: r == _active ? null : () => setState(() => _active = r),
                  onDeleted: mine.length > 1 ? () => _pick(r) : null,
                  deleteButtonTooltipMessage: context.l10n.homeRemoveRegion,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 동네 한 줄. [region] 은 서버에 보내는 전체 이름, [label] 은 화면에 보이는 이름.
  Widget _regionTile(AuthService auth, String region, String label) {
    final isCurrent = region == _active;
    final isMine = _sel.contains(region);
    return ListTile(
      title: Text(label,
          style: TextStyle(
            fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent ? EggplantColors.primary : EggplantColors.textPrimary,
          )),
      trailing: Icon(
        isMine ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        color: isMine ? EggplantColors.primary : EggplantColors.textTertiary,
      ),
      onTap: () => _pick(region),
    );
  }

  Widget _searchField(String hint) => Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _searchCtl,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.all(32),
        child: Text(context.l10n.regionNoResults,
            textAlign: TextAlign.center,
            style: const TextStyle(color: EggplantColors.textSecondary)),
      );

  /// 한국 — 동네 한 목록 + 검색 (예전 그대로).
  List<Widget> _krList(AuthService auth) {
    final list = _filtered;
    return [
      _searchField(context.l10n.homeRegionSearchHint),
      Expanded(
        child: ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _regionTile(auth, list[i], list[i]),
        ),
      ),
    ];
  }

  /// 2단계의 1단계 — 都道府県 / Province 목록. 검색어가 있으면 전국 시·군도 바로 보여준다.
  List<Widget> _groupStep(AuthService auth) {
    final l10n = context.l10n;
    final q = _norm(_query.trim());
    final currentPref = _groupOf(auth.user?.region ?? '');
    final groups = _groups;
    final prefs = groups
        .where((p) => q.isEmpty || _norm(p).contains(q))
        .toList();
    final cities = q.isEmpty
        ? const <(String, String, String)>[]
        : [
            for (final p in groups)
              ..._cities(p).where((c) => _hit(q, c.$2, c.$3)),
          ];
    return [
      _searchField(l10n.regionPrefectureSearchHint),
      Expanded(
        child: prefs.isEmpty && cities.isEmpty
            ? _empty()
            : ListView(
                // 단계마다 key 가 달라야 시·군 단계가 Province 목록의 스크롤 위치를 물려받지 않는다.
                key: const ValueKey('region-groups'),
                children: [
                  for (final p in prefs) ...[
                    ListTile(
                      title: Text(p,
                          style: TextStyle(
                            fontWeight: p == currentPref
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: p == currentPref
                                ? EggplantColors.primary
                                : EggplantColors.textPrimary,
                          )),
                      subtitle: Text(
                          l10n.regionCityCount(_cities(p).length),
                          style: const TextStyle(
                              fontSize: 12,
                              color: EggplantColors.textSecondary)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _setPref(p),
                    ),
                    const Divider(height: 1),
                  ],
                  for (final c in cities) ...[
                    _regionTile(auth, c.$1, c.$1),
                    const Divider(height: 1),
                  ],
                ],
              ),
      ),
    ];
  }

  /// 2단계의 2단계 — 고른 都道府県 / Province 의 시·군.
  List<Widget> _cityStep(AuthService auth, String pref) {
    final l10n = context.l10n;
    final q = _norm(_query.trim());
    final cities = _cities(pref)
        .where((c) => q.isEmpty || _hit(q, c.$2, c.$3))
        .toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
        child: Row(
          children: [
            IconButton(
              tooltip: l10n.regionChangePrefecture,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              onPressed: () => _setPref(null),
            ),
            Expanded(
              child: Text(pref,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () => _setPref(null),
              child: Text(l10n.regionChangePrefecture),
            ),
          ],
        ),
      ),
      _searchField(l10n.regionCitySearchHint(pref)),
      Expanded(
        child: cities.isEmpty
            ? _empty()
            : ListView.separated(
                key: ValueKey('region-cities-$pref'),
                itemCount: cities.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) =>
                    _regionTile(auth, cities[i].$1, cities[i].$2),
              ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final twoStep = _isTwoStep;

    // 2단계(시·군)에서 뒤로가기는 상위 지역(都道府県 / Province) 목록으로.
    return PopScope(
      canPop: _pref == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _pref != null) _setPref(null);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.homeRegionSettingsTitle)),
        bottomNavigationBar: _confirmBar(auth),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Responsive.maxFeedWidth),
              child: Column(
                children: [
                  _buildVerifiedBanner(auth),
                  _myRegions(),
                  if (!twoStep) ..._krList(auth),
                  if (twoStep && _pref == null) ..._groupStep(auth),
                  if (twoStep && _pref != null) ..._cityStep(auth, _pref!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

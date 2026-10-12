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

  /// 일본 2단계 선택에서 고른 都道府県. null 이면 都道府県 목록 단계.
  String? _pref;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  bool get _isJp =>
      AppMarket.isJp(AppMarket.of(context.read<AuthService>().user));

  /// 내 시장(한국/일본) 동네만 — 일본어 사용자에게는 일본 지역만 보인다.
  List<String> get _regions =>
      AppRegions.forMarket(AppMarket.of(context.read<AuthService>().user));

  List<String> get _filtered {
    if (_query.isEmpty) return _regions;
    return _regions
        .where((r) => r.toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  /// 검색어 정규화 — 소문자, 공백 제거, ひらがな → カタカナ (읽기 가나로도 찾게).
  static String _norm(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      if (r == 0x20 || r == 0x3000) continue;
      b.writeCharCode(r >= 0x3041 && r <= 0x3096 ? r + 0x60 : r);
    }
    return b.toString();
  }

  static bool _hit(String q, String name, String kana) =>
      _norm(name).contains(q) || kana.contains(q);

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

  /// 동네 누르기 — 내 동네 목록에 있으면 빼고, 없으면 추가하고 그 동네로 바꾼다 (최대 10곳).
  /// 화면은 닫지 않는다 — 여러 곳을 연달아 고를 수 있게.
  Future<void> _pick(AuthService auth, String r) async {
    final user = auth.user;
    final mine = user?.regions ?? const <String>[];
    if (mine.contains(r)) {
      if (mine.length <= 1) {
        _toast(context.l10n.regionKeepOne);
        return;
      }
      final next = [...mine]..remove(r);
      final err = await auth.setRegions(next, active: r == user?.region ? next.first : user?.region);
      if (!mounted) return;
      _toast(err ?? context.l10n.regionRemoved(r, next.length, _maxRegions));
      return;
    }
    if (mine.length >= _maxRegions) {
      _toast(context.l10n.homeMaxRegions(_maxRegions));
      return;
    }
    final err = await auth.updateRegion(r);
    if (!mounted) return;
    _toast(err ?? context.l10n.regionAdded(r, (auth.user?.regions.length ?? mine.length + 1), _maxRegions));
  }

  /// 위쪽 "내 동네 n/10" — 누르면 그 동네로 바꾸고, ✕ 로 뺀다.
  Widget _myRegions(AuthService auth) {
    final user = auth.user;
    final mine = user?.regions ?? const <String>[];
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
                  selected: r == user?.region,
                  showCheckmark: false,
                  selectedColor: EggplantColors.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    fontWeight: r == user?.region ? FontWeight.w800 : FontWeight.w500,
                    color: r == user?.region ? EggplantColors.primary : EggplantColors.textPrimary,
                  ),
                  onPressed: r == user?.region
                      ? null
                      : () async {
                          final err = await auth.updateRegion(r);
                          if (mounted) _toast(err ?? context.l10n.homeRegionSet(r));
                        },
                  onDeleted: mine.length > 1 ? () => _pick(auth, r) : null,
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
    final isCurrent = region == auth.user?.region;
    final isMine = auth.user?.regions.contains(region) ?? false;
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
      onTap: () => _pick(auth, region),
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

  /// 일본 1단계 — 都道府県 목록. 검색어가 있으면 전국 市区町村도 바로 보여준다.
  List<Widget> _jpPrefectureStep(AuthService auth) {
    final l10n = context.l10n;
    final q = _norm(_query.trim());
    final currentPref = AppRegions.jpPrefectureOf(auth.user?.region ?? '');
    final prefs = AppRegions.jpPrefectures
        .where((p) => q.isEmpty || _norm(p).contains(q))
        .toList();
    final cities = q.isEmpty
        ? const <(String, String, String)>[]
        : [
            for (final p in AppRegions.jpPrefectures)
              ...AppRegions.jpCities(p).where((c) => _hit(q, c.$2, c.$3)),
          ];
    return [
      _searchField(l10n.regionPrefectureSearchHint),
      Expanded(
        child: prefs.isEmpty && cities.isEmpty
            ? _empty()
            : ListView(
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
                          l10n.regionCityCount(AppRegions.jpCities(p).length),
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

  /// 일본 2단계 — 고른 都道府県의 市区町村.
  List<Widget> _jpCityStep(AuthService auth, String pref) {
    final l10n = context.l10n;
    final q = _norm(_query.trim());
    final cities = AppRegions.jpCities(pref)
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
    final isJp = _isJp;

    // 일본 2단계(市区町村)에서 뒤로가기는 都道府県 목록으로.
    return PopScope(
      canPop: _pref == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _pref != null) _setPref(null);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.homeRegionSettingsTitle)),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Responsive.maxFeedWidth),
              child: Column(
                children: [
                  _buildVerifiedBanner(auth),
                  _myRegions(auth),
                  if (!isJp) ..._krList(auth),
                  if (isJp && _pref == null) ..._jpPrefectureStep(auth),
                  if (isJp && _pref != null) ..._jpCityStep(auth, _pref!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

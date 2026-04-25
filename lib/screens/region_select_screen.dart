import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

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

  static const List<String> _regions = [
    '서울 강남구', '서울 강동구', '서울 강북구', '서울 강서구',
    '서울 관악구', '서울 광진구', '서울 구로구', '서울 금천구',
    '서울 노원구', '서울 도봉구', '서울 동대문구', '서울 동작구',
    '서울 마포구', '서울 서대문구', '서울 서초구', '서울 성동구',
    '서울 성북구', '서울 송파구', '서울 양천구', '서울 영등포구',
    '서울 용산구', '서울 은평구', '서울 종로구', '서울 중구', '서울 중랑구',
    '경기 수원시', '경기 성남시', '경기 용인시', '경기 고양시',
    '경기 부천시', '경기 안산시', '경기 안양시', '경기 남양주시',
    '경기 화성시', '경기 평택시', '경기 의정부시', '경기 시흥시',
    '경기 파주시', '경기 광명시', '경기 김포시', '경기 광주시',
    '인천 중구', '인천 동구', '인천 미추홀구', '인천 연수구',
    '인천 남동구', '인천 부평구', '인천 계양구', '인천 서구',
    '부산 해운대구', '부산 수영구', '부산 남구', '부산 연제구',
    '대구 중구', '대구 동구', '대구 서구', '대구 남구', '대구 북구',
    '대전 서구', '대전 유성구', '대전 중구',
    '광주 북구', '광주 남구', '광주 서구', '광주 동구',
    '울산 남구', '울산 중구', '울산 동구',
    '세종 세종시',
    '제주 제주시', '제주 서귀포시',
  ];

  List<String> get _filtered {
    if (_query.isEmpty) return _regions;
    return _regions
        .where((r) => r.toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  /// 동네 인증: GPS 좌표를 받아 서버에 검증 요청.
  /// 정확한 좌표는 서버에서 즉시 폐기되고 region 중심점만 저장된다.
  Future<void> _verifyWithGps({String? region}) async {
    if (_verifying) return;
    setState(() => _verifying = true);

    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      // 1) 위치 서비스(시스템 GPS) 켜져 있는지.
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) {
        messenger.showSnackBar(const SnackBar(
          content: Text('위치 서비스를 켜주세요 (설정 > 위치)'),
        ));
        return;
      }

      // 2) 권한.
      var perm = await Permission.locationWhenInUse.status;
      if (!perm.isGranted) {
        perm = await Permission.locationWhenInUse.request();
      }
      if (!perm.isGranted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('위치 권한이 필요해요. 설정에서 허용해주세요.'),
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
          content: Text('${auth.user?.region ?? "내 동네"} 인증 완료 🎉'),
          backgroundColor: EggplantColors.primary,
        ));
        if (Navigator.canPop(context)) context.pop();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('GPS 오류: $e')));
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
                  verified ? '동네 인증 완료' : '동네 인증 필요',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color:
                        verified ? EggplantColors.primary : Colors.orange[800],
                  ),
                ),
                Text(
                  verified
                      ? '$region · GPS 4km 이내 확인됨'
                      : '$region · GPS 인증으로 거리순 검색 가능해져요',
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
                : Text(verified ? '재인증' : '인증하기',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(title: const Text('내 동네 설정')),
      body: Column(
        children: [
          _buildVerifiedBanner(auth),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtl,
              decoration: const InputDecoration(
                hintText: '동, 읍, 면으로 검색 (예: 강남)',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _filtered[i];
                final isCurrent = r == auth.user?.region;
                return ListTile(
                  title: Text(r,
                      style: TextStyle(
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isCurrent
                            ? EggplantColors.primary
                            : EggplantColors.textPrimary,
                      )),
                  trailing: isCurrent
                      ? const Icon(Icons.check, color: EggplantColors.primary)
                      : null,
                  onTap: () async {
                    // 단순 region 변경 — GPS 인증은 풀린다.
                    await auth.updateRegion(r);
                    if (!context.mounted) return;
                    // 변경한 동네에서 바로 GPS 인증을 권유.
                    final verifyNow = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('동네 인증할까요?'),
                        content: Text(
                            '$r 에 정말 사는지 GPS 로 한 번만 확인하면 거리순 검색을 쓸 수 있어요.\n\n정확한 위치는 서버에 저장하지 않아요.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('나중에'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('지금 인증',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    );
                    if (verifyNow == true) {
                      await _verifyWithGps(region: r);
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$r 으로 설정되었어요')),
                      );
                      if (context.mounted && Navigator.canPop(context)) {
                        context.pop();
                      }
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

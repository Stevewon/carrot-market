import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(title: const Text('내 동네 설정')),
      body: Column(
        children: [
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
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isCurrent
                            ? EggplantColors.primary
                            : EggplantColors.textPrimary,
                      )),
                  trailing: isCurrent
                      ? const Icon(Icons.check, color: EggplantColors.primary)
                      : null,
                  onTap: () async {
                    await auth.updateRegion(r);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$r 으로 설정되었어요')),
                      );
                      context.pop();
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

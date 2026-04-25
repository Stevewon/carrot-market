import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/auth_service.dart';

/// 친구 초대 화면.
/// - 내 닉네임을 친구에게 알려주고, 친구가 회원가입 시 추천인 닉네임으로 입력하면
///   내가 +200 QTA 를 받음 (무제한).
/// - 친구가 탈퇴하면 해당 보너스는 즉시 회수됨.
class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthService>().api;
      final res = await api.dio.get('/api/referrals/me');
      if (res.statusCode == 200 && res.data is Map) {
        setState(() {
          _data = Map<String, dynamic>.from(res.data as Map);
          _loading = false;
        });
      } else {
        setState(() {
          _error = '불러오지 못했어요';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '서버에 연결할 수 없어요';
        _loading = false;
      });
    }
  }

  void _copyNickname(String nick) {
    Clipboard.setData(ClipboardData(text: nick));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('내 닉네임을 복사했어요. 친구에게 공유해주세요!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final myNick = auth.user?.nickname ?? '-';

    return Scaffold(
      appBar: AppBar(
        title: const Text('친구 초대'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 안내 카드
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: EggplantColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: EggplantColors.primary.withOpacity(0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.card_giftcard,
                          color: EggplantColors.primary, size: 22),
                      SizedBox(width: 8),
                      Text(
                        '친구 1명당 +200 QTA',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: EggplantColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '친구가 회원가입 시 추천인 닉네임에 내 닉네임을 입력하면\n'
                    '나에게 +200 QTA 가 자동 지급돼요. (무제한)\n'
                    '친구도 가입 보너스 +500 QTA를 받아요.',
                    style: TextStyle(
                      fontSize: 13,
                      color: EggplantColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: EggplantColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline,
                            color: EggplantColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            myNick,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: EggplantColors.textPrimary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _copyNickname(myNick),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('닉네임 복사'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              )
            else
              _buildList(),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EggplantColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '친구가 탈퇴하면 받았던 200 QTA 는 즉시 회수돼요. '
                      '(개인정보 보호 정책: 한 번 사라진 데이터는 영구 보관하지 않아요)',
                      style: TextStyle(
                        fontSize: 12,
                        color: EggplantColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final d = _data ?? const <String, dynamic>{};
    final granted = (d['granted_count'] as num?)?.toInt() ?? 0;
    final clawed = (d['clawed_back_count'] as num?)?.toInt() ?? 0;
    final net = (d['net'] as num?)?.toInt() ?? 0;
    final items = (d['items'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 통계
        Row(
          children: [
            _StatBox(label: '초대 성공', value: '$granted명', color: Colors.green),
            const SizedBox(width: 8),
            _StatBox(
                label: '회수됨',
                value: '$clawed명',
                color: clawed > 0 ? Colors.orange : Colors.grey),
            const SizedBox(width: 8),
            _StatBox(
                label: '누적 +QTA',
                value: '$net',
                color: EggplantColors.primary),
          ],
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '초대 내역',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: EggplantColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: EggplantColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '아직 초대한 친구가 없어요.\n위의 닉네임을 친구에게 공유해보세요!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: EggplantColors.textSecondary,
                height: 1.5,
              ),
            ),
          )
        else
          ...items.map((raw) {
            final item = Map<String, dynamic>.from(raw as Map);
            return _RefereeTile(item: item);
          }),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: EggplantColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefereeTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _RefereeTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final status = item['status']?.toString() ?? 'granted';
    final clawed = status == 'clawed_back';
    final nick = item['referee_nickname']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EggplantColors.border),
      ),
      child: Row(
        children: [
          Icon(
            clawed
                ? Icons.person_off_outlined
                : Icons.person_outline,
            color: clawed ? Colors.orange : EggplantColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clawed ? '(탈퇴한 사용자)' : (nick ?? '알 수 없음'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  clawed ? '친구가 탈퇴해 보너스가 회수되었어요' : '+200 QTA 적립됨',
                  style: TextStyle(
                    fontSize: 12,
                    color: clawed ? Colors.orange : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          Text(
            clawed ? '-200' : '+200',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: clawed ? Colors.orange : Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}

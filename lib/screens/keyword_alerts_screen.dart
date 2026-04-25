import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/keyword_alert_service.dart';

/// 키워드 알림 관리 화면 (당근식).
///
/// 사용자가 등록한 키워드는 새 상품이 올라올 때마다 일치 여부를 검사하고,
/// 매칭되면 WebSocket 으로 푸시가 오며 NotificationService 가 시스템 알림을 띄운다.
/// 알림 이력은 어디에도 저장하지 않는다 (사생활 보호).
class KeywordAlertsScreen extends StatefulWidget {
  const KeywordAlertsScreen({super.key});

  @override
  State<KeywordAlertsScreen> createState() => _KeywordAlertsScreenState();
}

class _KeywordAlertsScreenState extends State<KeywordAlertsScreen> {
  final TextEditingController _ctl = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KeywordAlertService>().load();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final raw = _ctl.text.trim();
    if (raw.isEmpty || _adding) return;
    setState(() => _adding = true);
    final svc = context.read<KeywordAlertService>();
    final err = await svc.add(raw);
    if (!mounted) return;
    setState(() => _adding = false);
    if (err == null) {
      _ctl.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  Future<void> _confirmRemove(KeywordAlertItem k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('키워드 삭제'),
        content: Text('"${k.keyword}" 알림을 끌까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<KeywordAlertService>().remove(k.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<KeywordAlertService>(
      builder: (context, svc, _) {
        return Scaffold(
          backgroundColor: EggplantColors.background,
          appBar: AppBar(
            title: const Text('키워드 알림'),
            elevation: 0,
            backgroundColor: Colors.white,
          ),
          body: Column(
            children: [
              // ── 입력 영역 ──
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '관심 키워드를 등록하면 동네에 새 매물이 올라올 때 알림을 보내드려요. (최대 ${svc.max}개)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: EggplantColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctl,
                            enabled: !svc.isFull && !_adding,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _add(),
                            maxLength: 30,
                            decoration: InputDecoration(
                              hintText: svc.isFull
                                  ? '키워드 슬롯이 모두 찼어요'
                                  : '예: 닌텐도, 자전거, 캠핑',
                              counterText: '',
                              filled: true,
                              fillColor: EggplantColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed:
                                (svc.isFull || _adding) ? null : _add,
                            child: _adding
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('등록'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ── 등록 키워드 목록 ──
              Expanded(
                child: svc.loading && !svc.loaded
                    ? const Center(child: CircularProgressIndicator())
                    : svc.items.isEmpty
                        ? const _Empty()
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: svc.items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final k = svc.items[i];
                              return Container(
                                color: Colors.white,
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.notifications_active,
                                    color: EggplantColors.primary,
                                  ),
                                  title: Text(
                                    k.keyword,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      size: 20,
                                    ),
                                    onPressed: () => _confirmRemove(k),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.notifications_off_outlined,
            size: 56,
            color: EggplantColors.textTertiary,
          ),
          SizedBox(height: 12),
          Text(
            '등록한 키워드가 없어요',
            style: TextStyle(
              fontSize: 15,
              color: EggplantColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '위에서 관심 키워드를 추가해보세요',
            style: TextStyle(
              fontSize: 13,
              color: EggplantColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

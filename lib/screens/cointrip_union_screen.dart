import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/constants.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/cointrip_service.dart';

/// 친구 연합 — 연합원 누가 주워도 함께 나눠 받는다. 주운 사람은 배수(처음 2배)만큼 더.
class CointripUnionScreen extends StatefulWidget {
  /// 연합 초대 링크로 들어오면 초대 코드 — 들어가기 칸에 미리 채운다.
  final String? code;
  const CointripUnionScreen({super.key, this.code});

  @override
  State<CointripUnionScreen> createState() => _CointripUnionScreenState();
}

class _CointripUnionScreenState extends State<CointripUnionScreen> {
  final _name = TextEditingController();
  late final _code = TextEditingController(text: (widget.code ?? '').trim().toUpperCase());
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CointripService>().refreshUnion().catchError((_) {});
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on CtError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 연합 초대 링크 보내기 — 받은 친구는 웹 페이지에서 앱으로 들어와 [연합 들어가기] 한 번이면 된다.
  Future<void> _shareInvite(CtUnion u) async {
    final l10n = context.l10n;
    final text = '${l10n.ctUnionShareText(u.code)}\n${AppConfig.apiBase}/c/${u.code}';
    try {
      await const MethodChannel('eggplant.market/share').invokeMethod('shareText', {'text': text, 'title': u.name});
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.ctUnionCopied)));
    }
  }

  Future<bool> _confirm(String msg, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  /// 예) 3명 연합에서 30개 — 서버 splitShares 와 같게 정수로: 나머지는 floor(30/(m+2))개씩, 주운 사람은 남은 전부.
  String _example(double m) {
    const total = 30;
    final each = (total / (m + 2)).floor();
    return context.l10n.ctUnionExample('$total', '${total - each * 2}', '$each');
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<CointripService>();
    final me = context.read<AuthService>().user?.id;
    final l10n = context.l10n;
    final u = svc.union;
    final mult = svc.finderMultiplier == svc.finderMultiplier.roundToDouble()
        ? svc.finderMultiplier.toInt().toString()
        : svc.finderMultiplier.toString();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(l10n.ctUnion)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: EggplantColors.background, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.ctUnionDesc(mult, svc.unionMax), style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 6),
                Text(_example(svc.finderMultiplier), style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary, height: 1.45)),
                const SizedBox(height: 6),
                Text(l10n.ctUnionWalletNote, style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary, height: 1.45)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (u == null) ...[
            Text(l10n.ctUnionCreate, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              maxLength: 20,
              decoration: InputDecoration(labelText: l10n.ctUnionName, border: const OutlineInputBorder()),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _run(() => svc.createUnion(_name.text.trim())),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(l10n.ctUnionCreate),
            ),
            const SizedBox(height: 28),
            Text(l10n.ctUnionJoin, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: InputDecoration(labelText: l10n.ctUnionCode, border: const OutlineInputBorder()),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(() => svc.joinUnion(_code.text.trim())),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(l10n.ctUnionJoinButton),
            ),
          ] else ...[
            Text(u.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(border: Border.all(color: EggplantColors.border), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.ctUnionCode, style: const TextStyle(fontSize: 12.5, color: EggplantColors.textSecondary)),
                        Text(u.code, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: l10n.ctUnionShareText(u.code)));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.ctUnionCopied)));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(l10n.ctUnionCopy),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _shareInvite(u),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.share_rounded, size: 20),
              label: Text(l10n.ctUnionShareLink, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/cointrip/union/chat'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.forum_outlined, size: 20),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(l10n.ctUnionChat, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (context.watch<ChatService>().unionUnread > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: EggplantColors.error, borderRadius: BorderRadius.circular(10)),
                      child: Text('${context.watch<ChatService>().unionUnread}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(l10n.ctUnionMembers(u.members.length, svc.unionMax), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final m in u.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: EggplantColors.primary.withValues(alpha: 0.12),
                  child: Text(m.nickname.isEmpty ? '?' : m.nickname.characters.first,
                      style: const TextStyle(color: EggplantColors.primary, fontWeight: FontWeight.w800)),
                ),
                title: Text(m.userId == me ? '${m.nickname} (${l10n.ctMe})' : m.nickname,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: m.userId == u.ownerId ? Text(l10n.ctUnionOwner) : null,
                trailing: u.ownerId == me && m.userId != me
                    ? TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await _confirm(l10n.ctUnionKickConfirm(m.nickname), l10n.ctUnionKick)) {
                                  _run(() => svc.kick(m.userId));
                                }
                              },
                        child: Text(l10n.ctUnionKick, style: const TextStyle(color: EggplantColors.error)),
                      )
                    : null,
              ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _confirm(l10n.ctUnionLeaveConfirm, l10n.ctUnionLeave)) _run(svc.leaveUnion);
                    },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: EggplantColors.error,
              ),
              child: Text(l10n.ctUnionLeave),
            ),
          ],
        ],
      ),
    );
  }
}

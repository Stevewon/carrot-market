import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/cointrip_service.dart';

/// 친구 연합 — 연합원 누가 주워도 함께 나눠 받는다. 주운 사람은 배수(처음 2배)만큼 더.
class CointripUnionScreen extends StatefulWidget {
  const CointripUnionScreen({super.key});

  @override
  State<CointripUnionScreen> createState() => _CointripUnionScreenState();
}

class _CointripUnionScreenState extends State<CointripUnionScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
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

  /// 예) 3명 연합에서 30개 → 주운 사람 m/(m+2), 나머지 1/(m+2).
  String _example(double m) {
    String f(double v) {
      final s = v.toStringAsFixed(2);
      return s.replaceFirst(RegExp(r'\.?0+$'), '');
    }

    const total = 30.0;
    final each = total / (m + 2);
    return context.l10n.ctUnionExample(f(total), f(total - each * 2), f(each));
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

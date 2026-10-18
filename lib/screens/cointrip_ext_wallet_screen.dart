import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/cointrip_service.dart';
import '../widgets/cointrip_notice.dart';

/// 일반 코인을 받을 기존 지갑 주소 — [solana] 면 솔라나 주소, 아니면 이더리움·BNB·폴리곤 공용 0x 주소.
/// 빨간 책임 안내를 확인해야 저장된다.
class CointripExtWalletScreen extends StatefulWidget {
  final bool solana;
  const CointripExtWalletScreen({super.key, this.solana = false});

  @override
  State<CointripExtWalletScreen> createState() => _CointripExtWalletScreenState();
}

class _CointripExtWalletScreenState extends State<CointripExtWalletScreen> {
  late final TextEditingController _c = TextEditingController(text: _current(context.read<CointripService>()) ?? '');
  bool _ack = false;
  bool _saving = false;
  String? _error;

  static final _evm = RegExp(r'^0x[0-9a-fA-F]{40}$');
  static final _sol = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');

  String? _current(CointripService s) => widget.solana ? s.solWallet : s.extWallet;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _valid => (widget.solana ? _sol : _evm).hasMatch(_c.text.trim());

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim();
    if (t != null && t.isNotEmpty) setState(() => _c.text = t);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<CointripService>().setWallet(_c.text.trim(), solana: widget.solana);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.ctSaved)));
      Navigator.pop(context);
    } on CtError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(widget.solana ? l10n.ctSolRemoveConfirm : l10n.ctRemoveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.ctRemove)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<CointripService>().removeWallet(solana: widget.solana);
      if (mounted) Navigator.pop(context);
    } on CtError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final has = _current(context.watch<CointripService>()) != null;
    final text = _c.text.trim();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.solana ? l10n.ctSolWallet : l10n.ctExtWallet),
        actions: [
          if (has) TextButton(onPressed: _remove, child: Text(l10n.ctRemove, style: const TextStyle(color: EggplantColors.error))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(widget.solana ? l10n.ctSolWalletDesc : l10n.ctExtWalletDesc,
              style: const TextStyle(fontSize: 14, height: 1.5, color: EggplantColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            maxLength: widget.solana ? 44 : 42,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.ctExtWalletLabel,
              hintText: widget.solana ? null : '0x…',
              border: const OutlineInputBorder(),
              errorText: text.isNotEmpty && !_valid ? (widget.solana ? l10n.ctSolWalletInvalid : l10n.ctExtWalletInvalid) : null,
              errorMaxLines: 2,
              suffixIcon: IconButton(tooltip: l10n.ctPaste, icon: const Icon(Icons.content_paste_rounded), onPressed: _paste),
            ),
          ),
          const SizedBox(height: 8),
          WalletResponsibilityAck(value: _ack, onChanged: (v) => setState(() => _ack = v)),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: EggplantColors.error, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _valid && _ack && !_saving ? _save : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(l10n.ctSave, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

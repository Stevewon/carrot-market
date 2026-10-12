import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/l10n.dart';
import '../app/theme.dart';

/// 언어 선택 — 큐알챗처럼 첫 실행 때 한 번 고르고, 마이페이지 "언어"에서 바꾼다.
///   한국어 → 새로 가입하면 한국 동네 · 원화
///   日本語 → 새로 가입하면 일본 지역 · 엔화
///   English → 새로 가입하면 필리핀 지역 · 페소
/// 문구는 세 언어를 함께 적는다 (아직 언어를 모르는 상태라서).
/// [onDone] 이 없으면(첫 실행) 고른 뒤 그대로 앱이 다시 그려져 다음 화면으로 넘어간다.
class LanguageSelectScreen extends StatefulWidget {
  final VoidCallback? onDone;
  const LanguageSelectScreen({super.key, this.onDone});

  @override
  State<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends State<LanguageSelectScreen> {
  late String _sel = L10n.lang;
  bool _saving = false;

  static const _labels = {
    'ko': ['한국어', 'Korean · 韓国語', '한국 동네 · 원화'],
    'ja': ['日本語', 'Japanese · 일본어', '日本の地域 · 円'],
    'en': ['English', '영어 · 英語', 'Philippines · Peso (₱)'],
  };

  /// 고른 언어로 쓴 문구 [ko, ja, en].
  String _t(List<String> v) => v[_sel == 'ja' ? 1 : _sel == 'en' ? 2 : 0];

  Future<void> _confirm() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await L10n.setLanguage(_sel, prefs);
    if (!mounted) return;
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.onDone == null
          ? null
          : AppBar(title: Text(_t(const ['언어', '言語', 'Language']))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onDone == null) ...[
                const Text('🍆', style: TextStyle(fontSize: 48), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                const Text(
                  '언어를 선택하세요\n言語を選択してください\nChoose your language',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                      color: EggplantColors.textPrimary),
                ),
                const SizedBox(height: 32),
              ],
              for (final code in const ['ko', 'ja', 'en'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _saving ? null : () => setState(() => _sel = code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _sel == code ? EggplantColors.primary : EggplantColors.border,
                          width: _sel == code ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_labels[code]![0],
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: EggplantColors.textPrimary)),
                                const SizedBox(height: 2),
                                Text('${_labels[code]![1]} · ${_labels[code]![2]}',
                                    style: const TextStyle(
                                        fontSize: 12, color: EggplantColors.textSecondary)),
                              ],
                            ),
                          ),
                          Icon(
                            _sel == code
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: _sel == code
                                ? EggplantColors.primary
                                : EggplantColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.onDone != null)
                Text(
                  _t(const [
                    '이미 가입한 계정의 동네·화폐는 그대로예요.',
                    '登録済みアカウントの地域・通貨はそのままです。',
                    'Your existing account keeps its region and currency.',
                  ]),
                  style: const TextStyle(fontSize: 12, color: EggplantColors.textTertiary),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: _saving ? null : _confirm,
                child: Text(widget.onDone == null
                    ? _t(const ['시작하기', 'はじめる', 'Get started'])
                    : _t(const ['저장', '保存', 'Save'])),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

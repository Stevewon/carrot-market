// ============================================================
// profile_edit_screen.dart — 프로필 등록 / 닉네임 수정 (v1.0.112)
// ============================================================
// 정책:
//   1) 서버 PUT /api/users/me 가 닉네임 변경을 지원 (2~12자, 중복 차단).
//   2) AuthService.updateNickname() 이 로컬 user + SharedPreferences 갱신.
//   3) ChatService.sendMessage / CallService.startCall 은 auth.user!.nickname
//      을 즉시 참조 → 변경 직후부터 채팅·통화 닉네임 자동 연동.
//   4) 익명성 정책: 본인인증과 무관하게 닉네임만 사용 (전화번호/실명 X).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/auth_service.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nicknameCtl;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final currentNick = context.read<AuthService>().user?.nickname ?? '';
    _nicknameCtl = TextEditingController(text: currentNick);
    _nicknameCtl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _nicknameCtl.removeListener(_onChanged);
    _nicknameCtl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  /// 클라이언트 사전 검증 — 서버 검증과 동일 규칙 (2~12자, 공백 trim).
  String? _validateLocal(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '닉네임을 입력해주세요';
    if (trimmed.length < 2) return '닉네임은 2자 이상이어야 해요';
    if (trimmed.length > 12) return '닉네임은 12자 이하여야 해요';
    return null;
  }

  Future<void> _save() async {
    final value = _nicknameCtl.text.trim();
    final localErr = _validateLocal(value);
    if (localErr != null) {
      setState(() => _errorText = localErr);
      return;
    }

    final auth = context.read<AuthService>();
    final current = auth.user?.nickname;
    if (value == current) {
      // 변경 없음 — 그냥 닫기.
      if (mounted) context.pop();
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    final err = await auth.updateNickname(value);

    if (!mounted) return;
    setState(() => _saving = false);

    if (err != null) {
      setState(() => _errorText = err);
      return;
    }

    // 성공 — 안내 후 닫기.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('닉네임이 변경됐어요. 채팅·통화에 바로 반영돼요 ✨'),
        duration: Duration(seconds: 2),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('로그인이 필요해요')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '프로필 등록',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: EggplantColors.textPrimary,
          ),
        ),
        iconTheme: const IconThemeData(color: EggplantColors.textPrimary),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              // 마스코트 + 안내.
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: EggplantColors.background,
                    border: Border.all(
                        color: EggplantColors.primary, width: 2),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/eggplant-mascot.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  '채팅·통화에 표시될 내 닉네임을 설정하세요',
                  style: TextStyle(
                    fontSize: 14,
                    color: EggplantColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 닉네임 입력.
              const Text(
                '닉네임',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: EggplantColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nicknameCtl,
                enabled: !_saving,
                maxLength: 12,
                inputFormatters: [
                  // 줄바꿈 차단.
                  FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
                ],
                decoration: InputDecoration(
                  hintText: '2~12자, 한글/영문/숫자',
                  errorText: _errorText,
                  counterText: '${_nicknameCtl.text.trim().length}/12',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: EggplantColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: EggplantColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: EggplantColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
                onSubmitted: (_) => _save(),
              ),

              const SizedBox(height: 12),

              // 안내 박스.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEDE9FE)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: EggplantColors.primary),
                        SizedBox(width: 6),
                        Text(
                          '닉네임 안내',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: EggplantColors.primary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• 변경 즉시 채팅·통화에 반영돼요\n'
                      '• 다른 사용자와 중복될 수 없어요\n'
                      '• 본인인증과 무관하게 닉네임만 사용해요',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: EggplantColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 저장 버튼.
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EggplantColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('저장하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

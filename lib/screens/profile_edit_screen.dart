// ============================================================
// profile_edit_screen.dart — 프로필 등록 / 닉네임 수정 (v1.0.113)
// ============================================================
// 정책:
//   1) 서버 PUT /api/users/me 가 닉네임 변경을 지원 (2~12자, 중복 차단).
//   2) AuthService.updateNickname() 이 로컬 user + SharedPreferences 갱신.
//   3) ChatService.sendMessage / CallService.startCall 은 auth.user!.nickname
//      을 즉시 참조 → 변경 직후부터 채팅·통화 닉네임 자동 연동.
//   4) 익명성 정책: 본인인증과 무관하게 닉네임만 사용 (전화번호/실명 X).
//   5) ★ v1.0.113: 프로필 사진 등록/교체 (로컬 base64 저장).
//      - 미등록 → 기본 가지(eggplant-mascot) 표시
//      - 등록 시 → 사진으로 교체, 본인 화면(MY/채팅 헤더)에만 노출
// ============================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
  // ★ v1.0.113: 사진 선택 상태 — 저장 전 임시 base64.
  //   null = 변경 없음(기존 사진 유지), '' = 사진 삭제, 그 외 = 새 사진.
  String? _pendingImageB64;
  bool _imageDirty = false;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    final currentNick = context.read<AuthService>().user?.nickname ?? '';
    _nicknameCtl = TextEditingController(text: currentNick);
    _nicknameCtl.addListener(_onChanged);
  }

  /// ★ v1.0.113: 사진 선택 (갤러리). 1024px 이내로 리사이즈 + 75% JPEG 압축
  ///   → base64 저장 시 SharedPreferences 용량(보통 200KB 이하)이 충분.
  Future<void> _pickImage() async {
    if (_pickingImage || _saving) return;
    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 75,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      if (!mounted) return;
      setState(() {
        _pendingImageB64 = b64;
        _imageDirty = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진을 불러올 수 없어요: $e')),
      );
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  /// 등록된 사진을 삭제 → 기본 가지 마스코트로 복귀.
  void _removeImage() {
    setState(() {
      _pendingImageB64 = '';
      _imageDirty = true;
    });
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
    final nicknameChanged = value != current;

    if (!nicknameChanged && !_imageDirty) {
      // 변경 없음 — 그냥 닫기.
      if (mounted) context.pop();
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    // ★ v1.0.113: 사진 변경은 로컬 저장 — 서버 호출 불필요, 즉시 성공 처리.
    if (_imageDirty) {
      final b64 = _pendingImageB64;
      await auth.setProfileImageB64((b64 != null && b64.isNotEmpty) ? b64 : null);
    }

    String? err;
    if (nicknameChanged) {
      err = await auth.updateNickname(value);
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (err != null) {
      setState(() => _errorText = err);
      return;
    }

    // 성공 — 안내 후 닫기.
    final msg = nicknameChanged
        ? '프로필이 저장됐어요. 채팅·통화에 바로 반영돼요 ✨'
        : '프로필 사진이 저장됐어요 ✨';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
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
              // ★ v1.0.113: 프로필 사진 + 등록/변경/삭제 버튼.
              //   - _pendingImageB64 == null  → 기존 사진 그대로 노출
              //   - _pendingImageB64 == ''    → 사진 삭제 (기본 가지)
              //   - _pendingImageB64 != null  → 새로 고른 사진 미리보기
              Center(
                child: GestureDetector(
                  onTap: _pickingImage ? null : _pickImage,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _AvatarPreview(
                        currentB64: auth.profileImageB64,
                        pendingB64: _pendingImageB64,
                        size: 96,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: EggplantColors.primary,
                            border: Border.all(
                                color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _pickingImage || _saving ? null : _pickImage,
                      icon: const Icon(Icons.photo_library_outlined,
                          size: 16),
                      label: Text(
                        (auth.profileImageB64 != null &&
                                _pendingImageB64 != '')
                            ? '사진 변경'
                            : '사진 등록',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: EggplantColors.primary,
                      ),
                    ),
                    if ((auth.profileImageB64 != null &&
                            _pendingImageB64 != '') ||
                        (_pendingImageB64 != null &&
                            _pendingImageB64!.isNotEmpty))
                      TextButton.icon(
                        onPressed: _saving ? null : _removeImage,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('기본 가지로 변경'),
                        style: TextButton.styleFrom(
                          foregroundColor: EggplantColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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

/// ★ v1.0.113: 프로필 사진 미리보기.
///   우선순위: pendingB64(편집 중) > currentB64(저장됨) > 기본 가지.
class _AvatarPreview extends StatelessWidget {
  final String? currentB64;
  final String? pendingB64;
  final double size;
  const _AvatarPreview({
    required this.currentB64,
    required this.pendingB64,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    final pending = pendingB64;
    if (pending != null && pending.isEmpty) {
      // 사용자가 "기본 가지로 변경" 누른 상태.
      child = Image.asset('assets/images/eggplant-mascot.png',
          fit: BoxFit.cover);
    } else {
      final b64 = (pending != null && pending.isNotEmpty)
          ? pending
          : currentB64;
      if (b64 != null && b64.isNotEmpty) {
        try {
          final bytes = _decode(b64);
          child = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        } catch (_) {
          child = Image.asset('assets/images/eggplant-mascot.png',
              fit: BoxFit.cover);
        }
      } else {
        child = Image.asset('assets/images/eggplant-mascot.png',
            fit: BoxFit.cover);
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: EggplantColors.background,
        border: Border.all(color: EggplantColors.primary, width: 2),
      ),
      child: ClipOval(child: SizedBox.expand(child: child)),
    );
  }

  static Uint8List _decode(String b64) {
    final i = b64.indexOf(',');
    final raw = (i >= 0) ? b64.substring(i + 1) : b64;
    return base64Decode(raw);
  }
}

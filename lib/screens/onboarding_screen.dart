import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EggplantColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              Image.asset(
                'assets/images/eggplant-mascot.png',
                width: 200,
                height: 200,
              ),
              const SizedBox(height: 32),
              const Text(
                'Eggplant',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: EggplantColors.primary,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '전화번호 없이, 완전 익명으로\n안전하게 중고거래하세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: EggplantColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              _FeatureRow(
                emoji: '🔐',
                title: 'QR 코드로만 연결',
                desc: '전화번호·이메일 없이 완벽한 익명',
              ),
              const SizedBox(height: 16),
              _FeatureRow(
                emoji: '💨',
                title: '휘발성 채팅',
                desc: '대화 내용은 서버/기기에 저장 안 됨',
              ),
              const SizedBox(height: 16),
              _FeatureRow(
                emoji: '🍆',
                title: '우리 동네 거래',
                desc: '내 동네 이웃과 안전하게',
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.push('/login'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('시작하기', style: TextStyle(fontSize: 17)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '가입 시 개인정보 수집 없음',
                style: TextStyle(
                  fontSize: 12,
                  color: EggplantColors.textTertiary,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String desc;

  const _FeatureRow({required this.emoji, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EggplantColors.border),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EggplantColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(desc,
                    style: const TextStyle(
                      fontSize: 13,
                      color: EggplantColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

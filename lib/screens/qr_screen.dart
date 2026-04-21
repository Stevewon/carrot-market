import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/theme.dart';
import '../services/auth_service.dart';

class QrScreen extends StatelessWidget {
  const QrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('로그인 후 이용해주세요')),
      );
    }

    final payload =
        'eggplant://${user.id}/${Uri.encodeComponent(user.nickname)}';

    return Scaffold(
      backgroundColor: EggplantColors.background,
      appBar: AppBar(
        backgroundColor: EggplantColors.background,
        title: const Text('내 QR 코드'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'QR 스캔',
            onPressed: () => context.push('/qr/scan'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              const Text(
                '상대방에게 QR을 보여주세요',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: EggplantColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'QR을 스캔하면 바로 익명 채팅이 시작돼요 💨',
                style: TextStyle(
                  fontSize: 13,
                  color: EggplantColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: EggplantColors.primary.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        QrImageView(
                          data: payload,
                          version: QrVersions.auto,
                          size: 240,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: EggplantColors.primary,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: EggplantColors.primary,
                          ),
                          embeddedImage: const AssetImage(
                            'assets/images/eggplant-mascot.png',
                          ),
                          embeddedImageStyle: const QrEmbeddedImageStyle(
                            size: Size(48, 48),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          user.nickname,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: EggplantColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '🔐 완전 익명 · 대화 저장 X',
                          style: TextStyle(
                            fontSize: 12,
                            color: EggplantColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: payload));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('QR 링크가 복사되었어요')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('QR 링크 복사'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

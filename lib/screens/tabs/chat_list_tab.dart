import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

class ChatListTab extends StatelessWidget {
  const ChatListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'QR 스캔',
            onPressed: () => context.push('/qr/scan'),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: EggplantColors.background,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.qr_code,
                size: 56,
                color: EggplantColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '💨 휘발성 채팅',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: EggplantColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Eggplant의 채팅은 저장되지 않아요.\n상품 상세에서 QR로 대화를 시작하면\n화면에만 대화가 보여요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: EggplantColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/qr'),
                  icon: const Icon(Icons.qr_code),
                  label: const Text('내 QR'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => context.push('/qr/scan'),
                  icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                  label: const Text('QR 스캔해서 채팅 시작'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

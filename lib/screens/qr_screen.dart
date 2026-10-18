import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/constants.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import 'peer_link_screen.dart';

class QrScreen extends StatelessWidget {
  const QrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(context.l10n.homeLoginToUse)),
      );
    }

    // https 링크 — 폰 카메라로 찍어도, 카톡에 붙여도 눌러서 앱으로 들어온다.
    final payload = peerLink(AppConfig.apiBase, user.id, user.nickname);

    return Scaffold(
      backgroundColor: EggplantColors.background,
      appBar: AppBar(
        backgroundColor: EggplantColors.background,
        title: Text(context.l10n.homeMyQr),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: context.l10n.homeQrScan,
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
              Text(
                context.l10n.homeShowQr,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: EggplantColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.homeQrDesc,
                style: const TextStyle(
                  fontSize: 13,
                  color: EggplantColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  // 큰 글씨(1.3배)에서 세로로 넘치면 스크롤.
                  child: SingleChildScrollView(
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
                          // 320폭(폴드 커버 등)에서 고정 240 이 가로로 넘쳤다 → 화면 폭에 맞춤.
                          size: (MediaQuery.of(context).size.width - 112).clamp(160.0, 240.0),
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
                          context.l10n.homeQrAnonymous,
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
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: payload));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.homeQrLinkCopied)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(context.l10n.homeQrCopyLink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

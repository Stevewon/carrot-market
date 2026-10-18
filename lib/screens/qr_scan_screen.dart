import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'peer_link_screen.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    _handled = true;
    final l10n = context.l10n;
    await _controller.stop();

    // 새 QR (https://…/u/<id>?n=…) · 예전 QR (eggplant://<id>/<닉네임>) 둘 다 읽는다.
    final peer = parsePeerLink(code);
    if (peer == null) {
      _showError(l10n.homeQrNotEggplant);
      return;
    }
    final peerUserId = peer.$1;
    final peerNickname = peer.$2.isEmpty ? l10n.homeAnonymous : peer.$2;

    final auth = context.read<AuthService>();
    if (auth.user == null) {
      _showError(l10n.homeLoginToUse);
      return;
    }

    if (peerUserId == auth.user!.id) {
      _showError(l10n.homeQrOwn);
      return;
    }

    final chat = context.read<ChatService>();
    final room = await chat.openRoomWithPeer(
      peerUserId: peerUserId,
      peerNickname: peerNickname,
    );
    if (!mounted) return;
    if (room == null) {
      _showError(l10n.homeQrChatFailed);
      return;
    }
    context.go(
      '/chat/${room.id}?peer=${Uri.encodeComponent(peerNickname)}'
      '&peerId=${Uri.encodeComponent(peerUserId)}',
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    Future.delayed(const Duration(seconds: 1), () {
      _handled = false;
      _controller.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // 검은 배경 — 상태바 아이콘을 밝게 (전역 기본은 어두운 아이콘).
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.l10n.homeQrScan, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (_, state, __) {
                final hasFlash = state.torchState != TorchState.unavailable;
                final on = state.torchState == TorchState.on;
                if (!hasFlash) return const SizedBox.shrink();
                return Icon(on ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white);
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.white),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Overlay
          Container(
            decoration: const BoxDecoration(color: Colors.black38),
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: EggplantColors.primary, width: 4),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            // 제스처바 영역만큼 띄워서 텍스트가 가리지 않게.
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 60),
                child: Column(
                  children: [
                    const Icon(Icons.qr_code_scanner, color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.homeQrScanGuide,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.homeQrScanDesc,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

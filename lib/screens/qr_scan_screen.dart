import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';

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
    await _controller.stop();

    final uri = Uri.tryParse(code);
    if (uri == null || uri.scheme != 'eggplant') {
      _showError('Eggplant QR이 아니에요');
      return;
    }

    final parts = uri.pathSegments;
    if (parts.length < 2) {
      _showError('잘못된 QR 형식이에요');
      return;
    }

    final peerUserId = uri.host; // eggplant://{userId}/{nickname}
    final peerNickname = Uri.decodeComponent(parts[0]);

    final auth = context.read<AuthService>();
    if (auth.user == null) {
      _showError('로그인 후 이용해주세요');
      return;
    }

    if (peerUserId == auth.user!.id) {
      _showError('내 QR은 스캔할 수 없어요');
      return;
    }

    final roomId = ChatService.roomIdFor(auth.user!.id, peerUserId);
    if (!mounted) return;
    context.go(
      '/chat/$roomId?peer=${Uri.encodeComponent(peerNickname)}'
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
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('QR 스캔', style: TextStyle(color: Colors.white)),
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
          const Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Icon(Icons.qr_code_scanner, color: Colors.white, size: 32),
                SizedBox(height: 8),
                Text(
                  'Eggplant QR을 프레임 안에 맞춰주세요',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text(
                  '스캔 즉시 익명 채팅이 시작돼요',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

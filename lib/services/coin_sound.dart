import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// 코인트립 코인을 주웠을 때 "띠롱" (assets/sounds/coin.wav) + 짧은 진동.
/// 듣던 음악을 멈추지 않게 다른 소리와 섞어 낸다. 무음 모드면 진동만.
class CoinSound {
  CoinSound._();

  static AudioPlayer? _player;

  static Future<void> play() async {
    // ignore: discarded_futures
    HapticFeedback.mediumImpact();
    try {
      final p = _player ??= AudioPlayer()
        ..setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build())
        ..setReleaseMode(ReleaseMode.stop)
        ..setPlayerMode(PlayerMode.lowLatency);
      await p.stop();
      await p.play(AssetSource('sounds/coin.wav'));
    } catch (_) {}
  }
}

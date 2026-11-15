import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PickedAudioData {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  PickedAudioData({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });
}

const MethodChannel _audioChannel = MethodChannel('verilens/android_audio');

Future<PickedAudioData?> pickAudioFromPlatform() async {
  if (!Platform.isAndroid) {
    throw Exception('Audio file picker is available on Android and Chrome Web.');
  }
  try {
    final res = await _audioChannel.invokeMethod<dynamic>('pickAudio');
    if (res is! Map) return null;
    final rawBytes = res['bytes'];
    if (rawBytes is! Uint8List) return null;
    return PickedAudioData(
      bytes: rawBytes,
      fileName: (res['fileName'] ?? 'voice_clip.m4a').toString(),
      mimeType: (res['mimeType'] ?? 'audio/mpeg').toString(),
    );
  } on PlatformException catch (e) {
    throw Exception(e.message ?? 'Could not pick audio file.');
  }
}

Future<PickedAudioData?> recordVoiceFromPlatform(BuildContext context) async {
  if (!Platform.isAndroid) {
    throw Exception('Live mic recording is available on Android and Chrome Web.');
  }
  try {
    await _audioChannel.invokeMethod<dynamic>('startRecording');
  } on PlatformException catch (e) {
    throw Exception(e.message ?? 'Could not start microphone.');
  }

  bool? shouldSave;
  try {
    if (!context.mounted) {
      await _audioChannel.invokeMethod<dynamic>('stopRecording', {'discard': true});
      return null;
    }
    shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AndroidMicRecordingDialog(),
    );
  } catch (_) {
    shouldSave = false;
  }

  try {
    final res = await _audioChannel.invokeMethod<dynamic>(
      'stopRecording',
      {'discard': shouldSave != true},
    );
    if (shouldSave != true || res is! Map) return null;
    final rawBytes = res['bytes'];
    if (rawBytes is! Uint8List) return null;
    return PickedAudioData(
      bytes: rawBytes,
      fileName: (res['fileName'] ?? 'live_voice_recording.m4a').toString(),
      mimeType: (res['mimeType'] ?? 'audio/mp4').toString(),
    );
  } on PlatformException catch (e) {
    throw Exception(e.message ?? 'Could not save recorded audio.');
  }
}

class _AndroidMicRecordingDialog extends StatefulWidget {
  const _AndroidMicRecordingDialog();

  @override
  State<_AndroidMicRecordingDialog> createState() =>
      _AndroidMicRecordingDialogState();
}

class _AndroidMicRecordingDialogState extends State<_AndroidMicRecordingDialog> {
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds += 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mins = (_seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_seconds % 60).toString().padLeft(2, '0');
    return AlertDialog(
      title: const Text('Recording Voice Sample'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(34),
            ),
            child: const Icon(Icons.mic, color: Color(0xFFB91C1C), size: 34),
          ),
          const SizedBox(height: 14),
          Text(
            '$mins:$secs',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Speak clearly into your phone mic, then tap Stop & Attach.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop & Attach'),
        ),
      ],
    );
  }
}
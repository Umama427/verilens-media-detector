// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';

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

Future<PickedAudioData?> pickAudioFromWeb() async {
  final input = html.FileUploadInputElement()
    ..accept = 'audio/*,.mp3,.wav,.m4a,.ogg,.webm';
  final completer = Completer<PickedAudioData?>();

  StreamSubscription<html.Event>? focusSub;
  focusSub = html.window.onFocus.listen((_) {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!completer.isCompleted && (input.files?.isEmpty ?? true)) {
        focusSub?.cancel();
        completer.complete(null);
      }
    });
  });

  input.onChange.listen((_) async {
    focusSub?.cancel();
    final files = input.files;
    if (files == null || files.isEmpty) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.first;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoadEnd.first;
    final result = reader.result;
    Uint8List? bytes;
    if (result is Uint8List) {
      bytes = result;
    } else if (result is ByteBuffer) {
      bytes = result.asUint8List();
    }
    if (!completer.isCompleted) {
      completer.complete(
        bytes == null
            ? null
            : PickedAudioData(
                bytes: bytes,
                fileName: file.name,
                mimeType: file.type.isNotEmpty ? file.type : 'audio/mpeg',
              ),
      );
    }
  });

  input.click();
  return completer.future;
}

Future<PickedAudioData?> recordVoiceFromWeb(BuildContext context) async {
  final mediaDevices = html.window.navigator.mediaDevices;
  if (mediaDevices == null) {
    throw Exception('Browser microphone API unavailable. Use localhost or HTTPS.');
  }

  final stream =
      await mediaDevices.getUserMedia({'audio': true, 'video': false});
  final recorder = html.MediaRecorder(stream);
  final chunks = <html.Blob>[];

  recorder.addEventListener('dataavailable', (html.Event e) {
    final blobEvent = e as html.BlobEvent;
    final data = blobEvent.data;
    if (data != null && data.size > 0) {
      chunks.add(data);
    }
  });

  recorder.start();

  if (!context.mounted) {
    recorder.stop();
    for (final track in stream.getTracks()) {
      track.stop();
    }
    return null;
  }

  final shouldSave = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _MicRecordingDialog(),
  );

  final stopFuture = recorder.onStop.first;
  recorder.stop();
  await stopFuture;

  for (final track in stream.getTracks()) {
    track.stop();
  }

  if (shouldSave != true || chunks.isEmpty) {
    return null;
  }

  final mime = (recorder.mimeType?.isNotEmpty ?? false)
      ? recorder.mimeType!
      : 'audio/webm';
  final combined = html.Blob(chunks, mime);
  final reader = html.FileReader();
  reader.readAsArrayBuffer(combined);
  await reader.onLoadEnd.first;

  final result = reader.result;
  Uint8List? bytes;
  if (result is Uint8List) {
    bytes = result;
  } else if (result is ByteBuffer) {
    bytes = result.asUint8List();
  }
  if (bytes == null) return null;

  return PickedAudioData(
    bytes: bytes,
    fileName: 'live_voice_recording.webm',
    mimeType: mime,
  );
}

class _MicRecordingDialog extends StatefulWidget {
  @override
  State<_MicRecordingDialog> createState() => _MicRecordingDialogState();
}

class _MicRecordingDialogState extends State<_MicRecordingDialog> {
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
            'Speak clearly into your microphone, then click Stop & Attach.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1D4ED8)),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop & Attach'),
        ),
      ],
    );
  }
}
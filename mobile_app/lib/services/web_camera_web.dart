// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

Future<Uint8List?> captureFromWebCamera(BuildContext context) async {
  final mediaDevices = html.window.navigator.mediaDevices;
  if (mediaDevices == null) {
    throw Exception('Browser webcam API unavailable. Use localhost or HTTPS.');
  }

  final stream =
      await mediaDevices.getUserMedia({'video': true, 'audio': false});
  final viewType = 'verilens-webcam-${DateTime.now().microsecondsSinceEpoch}';

  final video = html.VideoElement()
    ..autoplay = true
    ..muted = true
    ..srcObject = stream;
  video.style.width = '100%';
  video.style.height = '100%';
  video.style.objectFit = 'cover';
  video.setAttribute('playsinline', 'true');

  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) => video,
  );

  if (!context.mounted) {
    for (final track in stream.getTracks()) {
      track.stop();
    }
    return null;
  }

  final captured = await showDialog<Uint8List?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Live Webcam Capture'),
      content: SizedBox(
        width: 480,
        height: 340,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: HtmlElementView(viewType: viewType),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1D4ED8),
          ),
          onPressed: () {
            final w = video.videoWidth > 0 ? video.videoWidth : 640;
            final h = video.videoHeight > 0 ? video.videoHeight : 480;
            final canvas = html.CanvasElement(width: w, height: h);
            canvas.context2D.drawImageScaled(video, 0, 0, w, h);
            final dataUrl = canvas.toDataUrl('image/jpeg', 0.9);
            final base64Data = dataUrl.split(',').last;
            Navigator.of(ctx).pop(base64Decode(base64Data));
          },
          icon: const Icon(Icons.camera_alt),
          label: const Text('Capture Photo'),
        ),
      ],
    ),
  );

  for (final track in stream.getTracks()) {
    track.stop();
  }
  return captured;
}
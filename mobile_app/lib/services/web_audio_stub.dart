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

Future<PickedAudioData?> pickAudioFromPlatform() async {
  return null;
}

Future<PickedAudioData?> recordVoiceFromPlatform(BuildContext context) async {
  return null;
}
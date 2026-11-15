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
  return null;
}

Future<PickedAudioData?> recordVoiceFromWeb(BuildContext context) async {
  return null;
}
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'session_store.dart';

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String token;

  AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.token,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'token': token,
      };

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Forensic Analyst').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? 'Analyst').toString(),
      token: (json['token'] ?? '').toString(),
    );
  }
}

class MediaAnalysisResponse {
  final String classification;
  final int confidence;
  final String summary;
  final List<String> visualSignals;
  final String textConsistency;
  final String cumoNote;
  final String sourceChannel;
  final String mediaType;
  final String fileName;
  final String description;
  final String analyzedAt;

  MediaAnalysisResponse({
    required this.classification,
    required this.confidence,
    required this.summary,
    required this.visualSignals,
    required this.textConsistency,
    required this.cumoNote,
    required this.sourceChannel,
    required this.mediaType,
    required this.fileName,
    required this.description,
    required this.analyzedAt,
  });

  factory MediaAnalysisResponse.fromJson(Map<String, dynamic> json) {
    return MediaAnalysisResponse(
      classification: (json['classification'] ?? 'Suspicious').toString(),
      confidence: (json['confidence'] as num?)?.toInt() ?? 50,
      summary: (json['summary'] ?? '').toString(),
      visualSignals: (json['visualSignals'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      textConsistency: (json['textConsistency'] ?? '').toString(),
      cumoNote: (json['cumoNote'] ??
              'Cross-modal visual-caption verification completed.')
          .toString(),
      sourceChannel: (json['sourceChannel'] ?? 'Mobile App').toString(),
      mediaType: (json['mediaType'] ?? 'image').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      analyzedAt:
          (json['analyzedAt'] ?? DateTime.now().toIso8601String()).toString(),
    );
  }
}

class ApiService {
  static const String baseUrl = 'https://verilens-api-delta.vercel.app';

  static Map<String, dynamic> _safeJsonMap(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{
      'error':
          'Server returned HTTP ${response.statusCode}. Please check your connection and try again.',
    };
  }

  static Future<Map<String, dynamic>> checkHealth() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/health'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Backend offline (${response.statusCode})');
    }
    return _safeJsonMap(response);
  }

  static Future<String> sendRegisterOtp({
    required String name,
    required String email,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/send-register-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'email': email,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final decoded = _safeJsonMap(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Could not send OTP to your email.');
    }
    return (decoded['otpToken'] ?? '').toString();
  }

  static Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
    required String otp,
    required String otpToken,
    String role = 'Media Analyst',
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'email': cleanEmail,
            'password': password,
            'otp': otp,
            'otpToken': otpToken,
            'role': role,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final decoded = _safeJsonMap(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Registration failed.');
    }
    final proof = (decoded['accountProof'] ?? '').toString();
    if (proof.isNotEmpty) {
      saveStorageItem('verilens_proof_$cleanEmail', proof);
    }
    return AuthUser.fromJson({
      ...Map<String, dynamic>.from(decoded['user'] ?? {}),
      'token': decoded['token'] ?? '',
    });
  }

  static Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final savedProof = readStorageItem('verilens_proof_$cleanEmail') ?? '';
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': cleanEmail,
            'password': password,
            if (savedProof.isNotEmpty) 'accountProof': savedProof,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final decoded = _safeJsonMap(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Invalid email or password.');
    }
    final proof = (decoded['accountProof'] ?? '').toString();
    if (proof.isNotEmpty) {
      saveStorageItem('verilens_proof_$cleanEmail', proof);
    }
    return AuthUser.fromJson({
      ...Map<String, dynamic>.from(decoded['user'] ?? {}),
      'token': decoded['token'] ?? '',
    });
  }

  static Future<String> forgotPassword({
    required String email,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim().toLowerCase()}),
        )
        .timeout(const Duration(seconds: 20));

    final decoded = _safeJsonMap(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Could not send reset OTP email.');
    }
    return (decoded['resetToken'] ?? '').toString();
  }

  static Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
    required String resetToken,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': cleanEmail,
            'code': code,
            'newPassword': newPassword,
            'resetToken': resetToken,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final decoded = _safeJsonMap(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Password reset failed.');
    }
    final proof = (decoded['accountProof'] ?? '').toString();
    if (proof.isNotEmpty) {
      saveStorageItem('verilens_proof_$cleanEmail', proof);
    }
  }

  static Future<MediaAnalysisResponse> analyzeMedia({
    Uint8List? imageBytes,
    String fileName = 'uploaded_image.jpg',
    String mimeType = 'image/jpeg',
    String? sampleTag,
    required String description,
    String sourceChannel = 'Mobile App',
  }) async {
    String base64Image = '';
    if (imageBytes != null) {
      base64Image = base64Encode(imageBytes);
    } else if (sampleTag != null) {
      base64Image = base64Encode(utf8.encode('SAMPLE_MEDIA::$sampleTag'));
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/analyze'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'imageBase64': base64Image,
            'fileName': fileName,
            'mimeType': mimeType,
            'description': description,
            'sourceChannel': sourceChannel,
            'sampleTag': sampleTag ?? '',
          }),
        )
        .timeout(const Duration(seconds: 30));

    final decoded = _safeJsonMap(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          decoded['error'] ?? 'Analysis failed (${response.statusCode})');
    }

    return MediaAnalysisResponse.fromJson(decoded);
  }

  static Future<MediaAnalysisResponse> analyzeVoice({
    Uint8List? audioBytes,
    String fileName = 'voice_sample.wav',
    String mimeType = 'audio/wav',
    String? sampleTag,
    required String transcriptOrClaim,
    String sourceChannel = 'Voice Forensics',
  }) async {
    String base64Audio = '';
    if (audioBytes != null) {
      base64Audio = base64Encode(audioBytes);
    } else if (sampleTag != null) {
      base64Audio = base64Encode(utf8.encode('SAMPLE_VOICE::$sampleTag'));
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/analyze-voice'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'audioBase64': base64Audio,
            'fileName': fileName,
            'mimeType': mimeType,
            'transcriptOrClaim': transcriptOrClaim,
            'sourceChannel': sourceChannel,
            'sampleTag': sampleTag ?? '',
          }),
        )
        .timeout(const Duration(seconds: 30));

    final decoded = _safeJsonMap(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          decoded['error'] ?? 'Voice analysis failed (${response.statusCode})');
    }

    return MediaAnalysisResponse.fromJson(decoded);
  }

  static Future<List<MediaAnalysisResponse>> fetchScanHistory() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/scans'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Failed to load scans (${response.statusCode})');
    }
    final decoded = _safeJsonMap(response);
    final items = List<Map<String, dynamic>>.from(decoded['scans'] ?? []);
    return items.map(MediaAnalysisResponse.fromJson).toList();
  }

  static Future<int> trackApkShare() async {
    final response = await http
        .post(Uri.parse('$baseUrl/api/apk/track'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final decoded = _safeJsonMap(response);
      return (decoded['totalShares'] as num?)?.toInt() ?? 1;
    }
    return 1;
  }
}
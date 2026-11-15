import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

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
  final String classification; // Real | Fake | Suspicious
  final int confidence;
  final String summary;
  final List<String> visualSignals;
  final String textConsistency;
  final String cumoNote;
  final String sourceChannel;
  final String mediaType; // image | voice
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

  static Future<Map<String, dynamic>> checkHealth() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/health'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Backend offline (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
    String role = 'Media Analyst',
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'email': email,
            'password': password,
            'role': role,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Registration failed.');
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
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Invalid email or password.');
    }
    return AuthUser.fromJson({
      ...Map<String, dynamic>.from(decoded['user'] ?? {}),
      'token': decoded['token'] ?? '',
    });
  }

  static Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 15));

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Could not generate reset code.');
    }
    return decoded;
  }

  static Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
    required String resetToken,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'code': code,
            'newPassword': newPassword,
            'resetToken': resetToken,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Password reset failed.');
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Analysis failed (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Voice analysis failed (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return MediaAnalysisResponse.fromJson(decoded);
  }

  static Future<List<MediaAnalysisResponse>> fetchScanHistory() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/scans'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Failed to load scans (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final items = List<Map<String, dynamic>>.from(decoded['scans'] ?? []);
    return items.map(MediaAnalysisResponse.fromJson).toList();
  }

  static Future<int> trackApkShare() async {
    final response = await http
        .post(Uri.parse('$baseUrl/api/apk/track'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return (decoded['totalShares'] as num?)?.toInt() ?? 1;
    }
    return 1;
  }
}
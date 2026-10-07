import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, this.status);
  final String message;
  final int status;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.baseUrl, this.token, http.Client? client}) : _client = client ?? http.Client();

  String baseUrl;
  String? token;
  final http.Client _client;

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body);
  Future<dynamic> patch(String path, Map<String, dynamic> body) => _send('PATCH', path, body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<String> exportCsv() async {
    final response = await _request('GET', _uri('/export.csv'));
    if (response.statusCode >= 400) {
      throw ApiException(_message(response), response.statusCode);
    }
    return response.body;
  }

  Future<dynamic> _send(String method, String path, [Map<String, dynamic>? body]) async {
    try {
      return await _decode(await _request(method, _uri(path), body));
    } on TimeoutException {
      try {
        return await _decode(await _request(method, _uri(path), body));
      } on TimeoutException {
        throw ApiException('Could not reach Takings. Check your connection and try again.', 0);
      }
    }
  }

  Future<http.Response> _request(String method, Uri uri, [Map<String, dynamic>? body]) {
    final encoded = body == null ? null : jsonEncode(body);
    final headers = _headers();
    final Future<http.Response> response = switch (method) {
      'POST' => _client.post(uri, headers: headers, body: encoded),
      'PATCH' => _client.patch(uri, headers: headers, body: encoded),
      'DELETE' => _client.delete(uri, headers: headers),
      _ => _client.get(uri, headers: headers),
    };
    return response.timeout(const Duration(seconds: 30));
  }

  Future<dynamic> _decode(http.Response response) async {
    if (response.statusCode >= 400) {
      throw ApiException(_message(response), response.statusCode);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Uri _uri(String path) {
    final root = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$root$path');
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  String _message(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) return first['msg'] as String;
      }
    } catch (_) {}
    return 'Something went wrong (${response.statusCode})';
  }
}

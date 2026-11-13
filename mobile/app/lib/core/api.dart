import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'logic.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Der Server hat inzwischen einen neueren Stand; [current] ist dieser Stand.
class ConflictException implements Exception {
  const ConflictException(this.current);

  final Json current;
}

abstract interface class StichtagApi {
  Future<Json> pair(String pairingSecret, String deviceName);

  Future<Json> getState();

  Future<Json> putState(Json state);

  Future<void> logout();
}

/// Spricht per HTTPS mit dem Stichtag-Server. Zertifikate werden normal
/// geprüft, Weiterleitungen nicht verfolgt.
class HttpStichtagApi implements StichtagApi {
  HttpStichtagApi({required this.serverUrl, this.token}) {
    _client.connectionTimeout = _timeout;
  }

  static const _timeout = Duration(seconds: 15);

  final String serverUrl;
  final String? token;
  final HttpClient _client = HttpClient();

  @override
  Future<Json> pair(String pairingSecret, String deviceName) => _send(
    'POST',
    '/api/v1/pair',
    body: <String, dynamic>{
      'pairing_secret': pairingSecret,
      'device_name': deviceName,
    },
  );

  @override
  Future<Json> getState() => _send('GET', '/api/v1/state');

  @override
  Future<Json> putState(Json state) =>
      _send('PUT', '/api/v1/state', body: state);

  @override
  Future<void> logout() async {
    await _send('DELETE', '/api/v1/session');
  }

  Future<Json> _send(String method, String path, {Json? body}) async {
    final uri = Uri.parse('$serverUrl$path');
    if (uri.scheme != 'https') {
      throw const ApiException('Die Verbindung braucht HTTPS.');
    }
    try {
      final request = await _client.openUrl(method, uri).timeout(_timeout);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.acceptHeader, 'application/json');
      final bearer = token;
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(_timeout);
      final text = await utf8.decoder.bind(response).join().timeout(_timeout);
      dynamic decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      final data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final status = response.statusCode;
      if (status == 409) throw ConflictException(data);
      if (status == 401) {
        throw const ApiException(
          'Dieses Handy ist nicht mehr gekoppelt.',
          status: 401,
        );
      }
      if (status < 200 || status >= 300) {
        final message = data['error'];
        throw ApiException(
          message is String && message.isNotEmpty
              ? message
              : 'Der Server hat mit Fehler $status geantwortet.',
          status: status,
        );
      }
      return data;
    } on SocketException {
      throw const ApiException(
        'Der Server ist nicht erreichbar. Prüfe die Verbindung, zum Beispiel das VPN.',
      );
    } on HandshakeException {
      throw const ApiException(
        'Das Zertifikat des Servers konnte nicht geprüft werden.',
      );
    } on TimeoutException {
      throw const ApiException('Der Server antwortet nicht.');
    } on HttpException {
      throw const ApiException('Die Verbindung wurde unterbrochen.');
    }
  }
}

import 'package:dio/dio.dart';
import '../app/constants.dart';

class ApiClient {
  final Dio _dio;
  String? _token;

  ApiClient()
      : _dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBase,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null && _token!.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
    ));
  }

  void setToken(String? token) {
    _token = token;
  }

  /// ★ v1.0.149 (2026-05-10): JWT 첨부 상태 외부 점검용.
  ///   AgoraService 의 _requestToken 이 호출 직전 본 getter 로 인스턴스 분리
  ///   (AuthService.api ≠ AgoraService._api) 케이스를 탐지해 정확한 진단 토스트
  ///   ('JWT not attached') 노출.
  bool get hasToken => _token != null && _token!.isNotEmpty;

  Dio get dio => _dio;

  Future<Response> get(String path, {Map<String, dynamic>? query}) =>
      _dio.get(path, queryParameters: query);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> delete(String path) => _dio.delete(path);
}

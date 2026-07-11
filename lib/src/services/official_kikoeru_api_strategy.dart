import 'kikoeru_api_strategy.dart';
import 'cache_service.dart';
import 'log_service.dart';
import 'kikoeru_api_service.dart' show KikoeruApiException;

final _log = LogService.instance;

/// Strategy for the official ASMR.one server (api.asmr-*.com).
class OfficialKikoeruApiStrategy extends KikoeruApiStrategy {
  OfficialKikoeruApiStrategy(super.dio, super.config);

  @override
  bool get isOfficial => true;

  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await dio.post(
        '/api/auth/me',
        data: {'name': username, 'password': password},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Login failed', e);
    }
  }

  @override
  Future<Map<String, dynamic>> register(
      String username, String password) async {
    try {
      String recommenderUuid = '766cc58d-7f1e-4958-9a93-913400f378dc';

      final savedToken = config.token;
      final savedConfig = config;
      config = savedConfig.copyWith(token: null);

      try {
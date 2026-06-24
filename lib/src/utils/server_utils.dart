class ServerUtils {
  static const String officialHostKeyword = 'api.asmr';
  static const String defaultRemoteHost = 'https://api.asmr-200.com';
  static const String defaultLocalHost = 'localhost:8888';

  static const List<String> preferredHosts = [
    'api.asmr-200.com',
    'api.asmr.one',
    'api.asmr-100.com',
    'api.asmr-300.com',
  ];

  /// Checks if the provided host string corresponds to the official server.
  static bool isOfficialServer(String? host) {
    if (host == null || host.isEmpty) return false;
    return host.contains(officialHostKeyword);
  }

  /// Normalizes a host string to include the protocol prefix.
  /// Local addresses (localhost, 127.0.0.1, 192.168.x) get HTTP,
  /// everything else gets HTTPS.
  static String normalizeHost(String host) {
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return host;
    }
    if (host.contains('localhost') ||
        host.startsWith('127.0.0.1') ||
        host.startsWith('192.168.')) {
      return 'http://$host';
    }
    return 'https://$host';
  }
}

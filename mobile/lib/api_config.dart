/// Takings API. Production is the Alphabet VPS, same layout as Tanren.
class ApiConfig {
  static const productionUrl = 'https://api.takings.alphabet.lk';

  /// Android emulator talking to an API on this computer.
  static const androidEmulatorUrl = 'http://10.0.2.2:3120';

  /// iPhone simulator talking to an API on this computer.
  static const iosSimulatorUrl = 'http://127.0.0.1:3120';

  static const baseUrl = productionUrl;

  /// Takings Firebase project takings-88404. Web client is the Android serverClientId.
  static const googleServerClientId =
      '518774468117-mjr428jf41j77b4pgilg8lucm2l123qk.apps.googleusercontent.com';

  /// iOS OAuth client. Also set as GIDClientID in Info.plist.
  static const googleIosClientId =
      '518774468117-6bjos1h56mq7qps7kf2fqvhrujsl0a79.apps.googleusercontent.com';

  /// Android OAuth client for package lk.alphabet.takings.
  static const googleAndroidClientId =
      '518774468117-3ssda9pfgds9sv48hck5p6hm0j2mkjum.apps.googleusercontent.com';
}

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'mfrc522_method_channel.dart';

abstract class Mfrc522Platform extends PlatformInterface {
  /// Constructs a Mfrc522Platform.
  Mfrc522Platform() : super(token: _token);

  static final Object _token = Object();

  static Mfrc522Platform _instance = MethodChannelMfrc522();

  /// The default instance of [Mfrc522Platform] to use.
  ///
  /// Defaults to [MethodChannelMfrc522].
  static Mfrc522Platform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [Mfrc522Platform] when
  /// they register themselves.
  static set instance(Mfrc522Platform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}

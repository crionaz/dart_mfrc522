import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mfrc522_platform_interface.dart';

/// An implementation of [Mfrc522Platform] that uses method channels.
class MethodChannelMfrc522 extends Mfrc522Platform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('mfrc522');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}

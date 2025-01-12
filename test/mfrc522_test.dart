import 'package:flutter_test/flutter_test.dart';
import 'package:mfrc522/mfrc522.dart';
import 'package:mfrc522/mfrc522_platform_interface.dart';
import 'package:mfrc522/mfrc522_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockMfrc522Platform
    with MockPlatformInterfaceMixin
    implements Mfrc522Platform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final Mfrc522Platform initialPlatform = Mfrc522Platform.instance;

  test('$MethodChannelMfrc522 is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelMfrc522>());
  });

  test('getPlatformVersion', () async {
    Mfrc522 mfrc522Plugin = Mfrc522();
    MockMfrc522Platform fakePlatform = MockMfrc522Platform();
    Mfrc522Platform.instance = fakePlatform;

    expect(await mfrc522Plugin.getPlatformVersion(), '42');
  });
}

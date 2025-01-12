import 'package:mfrc522/mfrc522.dart';

class SimpleMfrc522 {
  final Mfrc522 mfrc522;
  final List<int> key;
  final int trailerBlock;

  SimpleMfrc522()
      : mfrc522 = Mfrc522(),
        key = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
        trailerBlock = 11;

  Future<Map<String, dynamic>> read() async {
    var result = await _readNoBlock(trailerBlock);
    while (result['id'] == null) {
      result = await _readNoBlock(trailerBlock);
    }
    return result;
  }

  Future<int?> readId() async {
    var id = await _readIdNoBlock();
    while (id == null) {
      id = await _readIdNoBlock();
    }
    return id;
  }

  Future<Map<String, dynamic>> write(String text) async {
    var result = await _writeNoBlock(text, trailerBlock);
    while (result['id'] == null) {
      await Future.delayed(Duration(milliseconds: 50));
      result = await _writeNoBlock(text, trailerBlock);
    }
    return result;
  }

  // Below are private methods adapted from those in BasicMFRC522

  Future<Map<String, dynamic>> _readNoBlock(int trailerBlock) async {
    try {
      if (!_checkTrailerBlock(trailerBlock)) {
        throw ArgumentError('Invalid Trailer Block $trailerBlock');
      }

      var blockAddr = [trailerBlock - 3, trailerBlock - 2, trailerBlock - 1];
      var result = await mfrc522.request(Mfrc522.piccReqIdl);
      if (result['status'] != Mfrc522.miOk) {
        return {'id': null, 'text': null};
      }

      result = await mfrc522.anticoll();
      if (result['status'] != Mfrc522.miOk) {
        return {'id': null, 'text': null};
      }

      var id = _uidToNum(result['uid']);
      await mfrc522.selectTag(result['uid']);
      var status = await mfrc522.authenticate(
          Mfrc522.piccAuthent1A, trailerBlock, key, result['uid']);

      var data = <int>[];
      var textRead = '';

      if (status == Mfrc522.miOk) {
        for (var blockNum in blockAddr) {
          var block = await mfrc522.readTag(blockNum);
          if (block != null) {
            data.addAll(block);
          }
        }
        if (data.isNotEmpty) {
          textRead = String.fromCharCodes(data);
        }
      }
      mfrc522.stopCrypto1();
      return {'id': id, 'text': textRead};
    } catch (e) {
      mfrc522.stopCrypto1();
      return {'id': null, 'text': null};
    }
  }

  Future<int?> _readIdNoBlock() async {
    var result = await mfrc522.request(Mfrc522.piccReqIdl);
    if (result['status'] != Mfrc522.miOk) {
      return null;
    }
    result = await mfrc522.anticoll();
    if (result['status'] != Mfrc522.miOk) {
      return null;
    }
    return _uidToNum(result['uid']);
  }

  Future<Map<String, dynamic>> _writeNoBlock(
      String text, int trailerBlock) async {
    try {
      if (!_checkTrailerBlock(trailerBlock)) {
        throw ArgumentError('Invalid Trailer Block');
      }

      var blockAddr = [trailerBlock - 3, trailerBlock - 2, trailerBlock - 1];
      var reqRes = await mfrc522.request(Mfrc522.piccReqIdl);
      if (reqRes['status'] != Mfrc522.miOk) {
        return {'id': null, 'text': null};
      }

      var collRes = await mfrc522.anticoll();
      if (collRes['status'] != Mfrc522.miOk) {
        return {'id': null, 'text': null};
      }

      var id = _uidToNum(collRes['uid']);
      var size = await mfrc522.selectTag(collRes['uid']);
      if (size == 0) {
        return {'id': null, 'text': null};
      }

      var auth = await mfrc522.authenticate(
          Mfrc522.piccAuthent1A, trailerBlock, key, collRes['uid']);
      if (auth != Mfrc522.miOk) {
        mfrc522.stopCrypto1();
        return {'id': null, 'text': null};
      }

      var data = text.padRight(blockAddr.length * 16).codeUnits;
      for (var i = 0; i < blockAddr.length; i++) {
        await mfrc522.writeTag(
            blockAddr[i], data.sublist(i * 16, (i + 1) * 16));
        await Future.delayed(Duration(milliseconds: 50));
      }

      mfrc522.stopCrypto1();
      return {'id': id, 'text': text, 'status': 'success'};
    } catch (e) {
      mfrc522.stopCrypto1();
      return {'id': null, 'text': null};
    }
  }

  bool _checkTrailerBlock(int trailerBlock) {
    return (trailerBlock + 1) % 4 == 0;
  }

  int _uidToNum(List<int> uid) {
    var n = 0;
    for (var i = 0; i < 5; i++) {
      n = n * 256 + uid[i];
    }
    return n;
  }
}

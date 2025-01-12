import 'dart:async';
import 'dart:typed_data';
import 'package:dart_periphery/dart_periphery.dart';
import 'package:logger/logger.dart';
import 'package:flutter_gpiod/flutter_gpiod.dart';
export 'simple_mfrc522.dart';

class Mfrc522 {

  static const int maxLen = 16;

  // PCD Commands
  static const int pcdIdle = 0x00;
  static const int pcdAuthEnt = 0x0E;
  static const int pcdReceive = 0x08;
  static const int pcdTransmit = 0x04;
  static const int pcdTransceive = 0x0C;
  static const int pcdResetPhase = 0x0F;
  static const int pcdCalcCrc = 0x03;

  // PICC Commands
  static const int piccReqIdl = 0x26;
  static const int piccReqAll = 0x52;
  static const int piccAntiColl = 0x93;
  static const int piccSelectTag = 0x93;
  static const int piccAuthent1A = 0x60;
  static const int piccAuthent1B = 0x61;
  static const int piccRead = 0x30;
  static const int piccWrite = 0xA0;
  static const int piccDecrement = 0xC0;
  static const int piccIncrement = 0xC1;
  static const int piccRestore = 0xC2;
  static const int piccTransfer = 0xB0;
  static const int piccHalt = 0x50;

  // Status
  static const int miOk = 0;
  static const int miNoTagErr = 1;
  static const int miErr = 2;

  // Mfrc522 Registers
  static const int reserved00 = 0x00;
  static const int commandReg = 0x01;
  static const int commIEnReg = 0x02;
  static const int divlEnReg = 0x03;
  static const int commIrqReg = 0x04;
  static const int divIrqReg = 0x05;
  static const int errorReg = 0x06;
  static const int status1Reg = 0x07;
  static const int status2Reg = 0x08;
  static const int fifoDataReg = 0x09;
  static const int fifoLevelReg = 0x0A;
  static const int waterLevelReg = 0x0B;
  static const int controlReg = 0x0C;
  static const int bitFramingReg = 0x0D;
  static const int collReg = 0x0E;
  static const int modeReg = 0x11;
  static const int txModeReg = 0x12;
  static const int rxModeReg = 0x13;
  static const int txControlReg = 0x14;
  static const int txAutoReg = 0x15;
  static const int tModeReg = 0x2A;
  static const int tPrescalerReg = 0x2B;
  static const int tReloadRegL = 0x2C;
  static const int tReloadRegH = 0x2D;
  static const int cRCResultRegL = 0x22; // CRC calculation result low byte
  static const int cRCResultRegM = 0x21; // CRC calculation result high byte

  late final SPI spi; // Changed from Spi to SPI (dart_periphery convention)
  late final Logger logger;
  late final GpioChip gpio;
  late final GpioLine resetPin;
  late final int pinRst;
  static GpioLine? _sharedResetPin; // Static shared reset pin

  Mfrc522(
      {int bus = 0,
      int device = 0,
      int spd = 1000000,
      int pinMode = 10,
      int pinRst = -1,
      String debugLevel = 'WARNING'}) {
    // Initialize SPI communication with proper mode
    spi = SPI.openAdvanced2(
      bus,
      device,
      "/dev/spidev$bus.$device",
      SPImode.mode0, // Mode 0 is required for Mfrc522
      spd, // max speed in Hz
      BitOrder.msbFirst, // MSB first
      8, // 8 bits per word
      0, // no extra flags
    );

    // Initialize logger
    logger = Logger(
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 5,
        lineLength: 50,
        colors: true,
        printEmojis: true,
      ),
    );

    // Initialize GPIO using flutter_gpiod
    gpio = FlutterGpiod.instance.chips[0]; // Get the first GPIO chip
    this.pinRst = (pinRst == -1) ? (pinMode == 11 ? 25 : 22) : pinRst;

    // Handle shared GPIO line
    if (_sharedResetPin == null) {
      resetPin = gpio.lines[this.pinRst];
      resetPin.requestOutput(
        consumer: "mfrc522",
        initialValue: true,
      );
      _sharedResetPin = resetPin;
    } else {
      resetPin = _sharedResetPin!;
    }

    init();
  }

  void reset() {
    writeReg(commandReg, pcdResetPhase);
  }

  void writeReg(int addr, int val) {
    var data = [(addr << 1) & 0x7E, val];
    spi.transfer(
        Uint8List.fromList(data), false); // Added reuseBuffer parameter
  }

  int readReg(int addr) {
    var data = [((addr << 1) & 0x7E) | 0x80, 0];
    var result = spi.transfer(
        Uint8List.fromList(data), false); // Added reuseBuffer parameter
    return result[1];
  }

  void close() {
    spi.dispose(); // Changed from close() to dispose()
    // Only release the GPIO if we're the last instance
    if (identical(resetPin, _sharedResetPin)) {
      resetPin.release();
      _sharedResetPin = null;
    }
  }

  void setBitMask(int reg, int mask) {
    var tmp = readReg(reg);
    writeReg(reg, tmp | mask);
  }

  void clearBitMask(int reg, int mask) {
    var tmp = readReg(reg);
    writeReg(reg, tmp & (~mask));
  }

  void antennaOn() {
    var temp = readReg(txControlReg);
    if ((temp & 0x03) != 0x03) {
      setBitMask(txControlReg, 0x03);
    }
  }

  void antennaOff() {
    clearBitMask(txControlReg, 0x03);
  }

  Future<void> delayMicroseconds(int us) async {
    await Future.delayed(Duration(microseconds: us));
  }

  Future<Map<String, dynamic>> mfrc522ToCard(
      int command, List<int> sendData) async {
    List<int> backData = [];
    int backLen = 0;
    int status = miErr;
    int irqEn = 0x00;
    int waitIRq = 0x00;

    if (command == pcdAuthEnt) {
      irqEn = 0x12;
      waitIRq = 0x10;
    }
    if (command == pcdTransceive) {
      irqEn = 0x77;
      waitIRq = 0x30;
    }

    writeReg(commIEnReg, irqEn | 0x80);
    clearBitMask(commIrqReg, 0x80);
    setBitMask(fifoLevelReg, 0x80);
    writeReg(commandReg, pcdIdle);

    for (var i = 0; i < sendData.length; i++) {
      writeReg(fifoDataReg, sendData[i]);
    }

    writeReg(commandReg, command);
    if (command == pcdTransceive) {
      setBitMask(bitFramingReg, 0x80);
    }

    int i = 2000;
    int n = 0;
    do {
      await delayMicroseconds(350); // Adding delay like in Python version
      n = readReg(commIrqReg);
      i--;
    } while (i != 0 && ((n & 0x01) == 0) && ((n & waitIRq) == 0));

    clearBitMask(bitFramingReg, 0x80);

    if (i != 0) {
      if ((readReg(errorReg) & 0x1B) == 0x00) {
        status = miOk;

        if ((n & irqEn & 0x01) != 0) {
          // Changed to compare with 0
          status = miNoTagErr;
        }

        if (command == pcdTransceive) {
          n = readReg(fifoLevelReg);
          int lastBits = readReg(controlReg) & 0x07;
          if (lastBits != 0) {
            backLen = (n - 1) * 8 + lastBits;
          } else {
            backLen = n * 8;
          }

          if (n == 0) {
            n = 1;
          }
          if (n > maxLen) {
            n = maxLen;
          }

          for (i = 0; i < n; i++) {
            backData.add(readReg(fifoDataReg));
          }
        }
      } else {
        status = miErr;
      }
    }

    return {
      'status': status,
      'backData': backData,
      'backLen': backLen,
    };
  }

  Future<Map<String, dynamic>> request(int reqMode) async {
    writeReg(bitFramingReg, 0x07);
    List<int> tagType = [reqMode];

    var result = await mfrc522ToCard(pcdTransceive, tagType);
    if ((result['status'] != miOk) || (result['backLen'] != 0x10)) {
      result['status'] = miErr;
    }

    return result;
  }

  Future<Map<String, dynamic>> anticoll() async {
    writeReg(bitFramingReg, 0x00);
    List<int> serNum = [piccAntiColl, 0x20];

    var result = await mfrc522ToCard(pcdTransceive, serNum);

    if (result['status'] == miOk) {
      var backData = result['backData'] as List<int>;
      if (backData.length == 5) {
        int serNumCheck = 0;
        for (int i = 0; i < 4; i++) {
          serNumCheck = serNumCheck ^ backData[i];
        }
        if (serNumCheck != backData[4]) {
          result['status'] = miErr;
        }
        result['uid'] = backData;
      } else {
        result['status'] = miErr;
      }
    }

    return result;
  }

  Future<List<int>> calculateCRC(List<int> pIndata) async {
    clearBitMask(divIrqReg, 0x04);
    setBitMask(fifoLevelReg, 0x80);

    for (int i = 0; i < pIndata.length; i++) {
      writeReg(fifoDataReg, pIndata[i]);
    }
    writeReg(commandReg, pcdCalcCrc);

    int i = 0xFF;
    while (true) {
      int n = readReg(divIrqReg);
      i--;
      if (i == 0 || (n & 0x04) > 0) break;
    }

    return [readReg(cRCResultRegL), readReg(cRCResultRegM)];
  }

  Future<int> selectTag(List<int> serNum) async {
    List<int> buf = [piccSelectTag, 0x70];
    buf.addAll(serNum);

    var crc = await calculateCRC(buf);
    buf.addAll(crc);

    var result = await mfrc522ToCard(pcdTransceive, buf);

    if (result['status'] == miOk && result['backLen'] == 0x18) {
      return result['backData'][0];
    }
    return 0;
  }

  Future<int> authenticate(int authMode, int blockAddr, List<int> sectorKey,
      List<int> serNum) async {
    List<int> buff = [authMode, blockAddr];
    buff.addAll(sectorKey);
    buff.addAll(serNum.sublist(0, 4));

    var result = await mfrc522ToCard(pcdAuthEnt, buff);

    if ((result['status'] != miOk) || ((readReg(status2Reg) & 0x08) == 0)) {
      return miErr;
    }

    return miOk;
  }

  void stopCrypto1() {
    clearBitMask(status2Reg, 0x08);
  }

  Future<List<int>?> readTag(int blockAddr) async {
    List<int> recvData = [piccRead, blockAddr];
    var crc = await calculateCRC(recvData);
    recvData.addAll(crc);

    var result = await mfrc522ToCard(pcdTransceive, recvData);

    if (result['status'] != miOk) {
      logger.e("Error while reading!");
      return null;
    }

    var backData = result['backData'] as List<int>;
    if (backData.length == 16) {
      logger.d("Sector $blockAddr $backData");
      return backData;
    }
    return null;
  }

  Future<void> writeTag(int blockAddr, List<int> writeData) async {
    List<int> buff = [piccWrite, blockAddr];
    var crc = await calculateCRC(buff);
    buff.addAll(crc);

    var result = await mfrc522ToCard(pcdTransceive, buff);
    if (result['status'] != miOk ||
        result['backLen'] != 4 ||
        (result['backData'][0] & 0x0F) != 0x0A) {
      logger.e("Error while writing");
      return;
    }

    List<int> buf = List.from(writeData);
    crc = await calculateCRC(buf);
    buf.addAll(crc);

    result = await mfrc522ToCard(pcdTransceive, buf);
    if (result['status'] != miOk ||
        result['backLen'] != 4 ||
        (result['backData'][0] & 0x0F) != 0x0A) {
      logger.e("Error while writing");
    } else {
      logger.d("Data written successfully");
    }
  }

  void init() {
    reset();
    writeReg(tModeReg, 0x8D);
    writeReg(tPrescalerReg, 0x3E);
    writeReg(tReloadRegL, 30);
    writeReg(tReloadRegH, 0);
    writeReg(txAutoReg, 0x40);
    writeReg(modeReg, 0x3D);
    antennaOn();
  }

  Future<void> dumpClassic1K(List<int> key, List<int> uid) async {
    logger.d("Dumping entire MIFARE 1K card...");
    // Typically 16 sectors of 4 blocks each = 64 blocks total
    for (int blockAddr = 0; blockAddr < 64; blockAddr++) {
      // Authenticate each block with key A
      int status =
          await authenticate(Mfrc522.piccAuthent1A, blockAddr, key, uid);
      if (status == miOk) {
        var blockData = await readTag(blockAddr);
        if (blockData != null) {
          logger.d("Block $blockAddr : $blockData");
        } else {
          logger.e("Failed reading block $blockAddr");
        }
        stopCrypto1();
      } else {
        logger.e("Authentication failed for block $blockAddr");
      }
    }
  }

  void dispose() {
    spi.dispose(); // Changed from close() to dispose()
    // Only release the GPIO if we're the last instance
    if (identical(resetPin, _sharedResetPin)) {
      resetPin.release();
      _sharedResetPin = null;
    }
  }
}

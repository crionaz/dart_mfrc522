
import 'mfrc522_platform_interface.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:dart_periphery/dart_periphery.dart';
import 'package:logger/logger.dart';
import 'package:flutter_gpiod/flutter_gpiod.dart';


class Mfrc522 {
  Future<String?> getPlatformVersion() {
    return Mfrc522Platform.instance.getPlatformVersion();
  }

  static const int MAX_LEN = 16;

  // PCD Commands
  static const int PCD_IDLE = 0x00;
  static const int PCD_AUTHENT = 0x0E;
  static const int PCD_RECEIVE = 0x08;
  static const int PCD_TRANSMIT = 0x04;
  static const int PCD_TRANSCEIVE = 0x0C;
  static const int PCD_RESETPHASE = 0x0F;
  static const int PCD_CALCCRC = 0x03;

  // PICC Commands
  static const int PICC_REQIDL = 0x26;
  static const int PICC_REQALL = 0x52;
  static const int PICC_ANTICOLL = 0x93;
  static const int PICC_SELECTTAG = 0x93;
  static const int PICC_AUTHENT1A = 0x60;
  static const int PICC_AUTHENT1B = 0x61;
  static const int PICC_READ = 0x30;
  static const int PICC_WRITE = 0xA0;
  static const int PICC_DECREMENT = 0xC0;
  static const int PICC_INCREMENT = 0xC1;
  static const int PICC_RESTORE = 0xC2;
  static const int PICC_TRANSFER = 0xB0;
  static const int PICC_HALT = 0x50;

  // Status
  static const int MI_OK = 0;
  static const int MI_NOTAGERR = 1;
  static const int MI_ERR = 2;

  // Mfrc522 Registers
  static const int Reserved00 = 0x00;
  static const int CommandReg = 0x01;
  static const int CommIEnReg = 0x02;
  static const int DivlEnReg = 0x03;
  static const int CommIrqReg = 0x04;
  static const int DivIrqReg = 0x05;
  static const int ErrorReg = 0x06;
  static const int Status1Reg = 0x07;
  static const int Status2Reg = 0x08;
  static const int FIFODataReg = 0x09;
  static const int FIFOLevelReg = 0x0A;
  static const int WaterLevelReg = 0x0B;
  static const int ControlReg = 0x0C;
  static const int BitFramingReg = 0x0D;
  static const int CollReg = 0x0E;
  static const int ModeReg = 0x11;
  static const int TxModeReg = 0x12;
  static const int RxModeReg = 0x13;
  static const int TxControlReg = 0x14;
  static const int TxAutoReg = 0x15;
  static const int TModeReg = 0x2A;
  static const int TPrescalerReg = 0x2B;
  static const int TReloadRegL = 0x2C;
  static const int TReloadRegH = 0x2D;
  static const int CRCResultRegL = 0x22; // CRC calculation result low byte
  static const int CRCResultRegM = 0x21; // CRC calculation result high byte

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
    writeReg(CommandReg, PCD_RESETPHASE);
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
    var temp = readReg(TxControlReg);
    if ((temp & 0x03) != 0x03) {
      setBitMask(TxControlReg, 0x03);
    }
  }

  void antennaOff() {
    clearBitMask(TxControlReg, 0x03);
  }

  Future<void> delayMicroseconds(int us) async {
    await Future.delayed(Duration(microseconds: us));
  }

  Future<Map<String, dynamic>> mfrc522ToCard(
      int command, List<int> sendData) async {
    List<int> backData = [];
    int backLen = 0;
    int status = MI_ERR;
    int irqEn = 0x00;
    int waitIRq = 0x00;

    if (command == PCD_AUTHENT) {
      irqEn = 0x12;
      waitIRq = 0x10;
    }
    if (command == PCD_TRANSCEIVE) {
      irqEn = 0x77;
      waitIRq = 0x30;
    }

    writeReg(CommIEnReg, irqEn | 0x80);
    clearBitMask(CommIrqReg, 0x80);
    setBitMask(FIFOLevelReg, 0x80);
    writeReg(CommandReg, PCD_IDLE);

    for (var i = 0; i < sendData.length; i++) {
      writeReg(FIFODataReg, sendData[i]);
    }

    writeReg(CommandReg, command);
    if (command == PCD_TRANSCEIVE) {
      setBitMask(BitFramingReg, 0x80);
    }

    int i = 2000;
    int n = 0;
    do {
      await delayMicroseconds(350); // Adding delay like in Python version
      n = readReg(CommIrqReg);
      i--;
    } while (i != 0 && ((n & 0x01) == 0) && ((n & waitIRq) == 0));

    clearBitMask(BitFramingReg, 0x80);

    if (i != 0) {
      if ((readReg(ErrorReg) & 0x1B) == 0x00) {
        status = MI_OK;

        if ((n & irqEn & 0x01) != 0) {
          // Changed to compare with 0
          status = MI_NOTAGERR;
        }

        if (command == PCD_TRANSCEIVE) {
          n = readReg(FIFOLevelReg);
          int lastBits = readReg(ControlReg) & 0x07;
          if (lastBits != 0) {
            backLen = (n - 1) * 8 + lastBits;
          } else {
            backLen = n * 8;
          }

          if (n == 0) {
            n = 1;
          }
          if (n > MAX_LEN) {
            n = MAX_LEN;
          }

          for (i = 0; i < n; i++) {
            backData.add(readReg(FIFODataReg));
          }
        }
      } else {
        status = MI_ERR;
      }
    }

    return {
      'status': status,
      'backData': backData,
      'backLen': backLen,
    };
  }

  Future<Map<String, dynamic>> request(int reqMode) async {
    writeReg(BitFramingReg, 0x07);
    List<int> tagType = [reqMode];

    var result = await mfrc522ToCard(PCD_TRANSCEIVE, tagType);
    if ((result['status'] != MI_OK) || (result['backLen'] != 0x10)) {
      result['status'] = MI_ERR;
    }

    return result;
  }

  Future<Map<String, dynamic>> anticoll() async {
    writeReg(BitFramingReg, 0x00);
    List<int> serNum = [PICC_ANTICOLL, 0x20];

    var result = await mfrc522ToCard(PCD_TRANSCEIVE, serNum);

    if (result['status'] == MI_OK) {
      var backData = result['backData'] as List<int>;
      if (backData.length == 5) {
        int serNumCheck = 0;
        for (int i = 0; i < 4; i++) {
          serNumCheck = serNumCheck ^ backData[i];
        }
        if (serNumCheck != backData[4]) {
          result['status'] = MI_ERR;
        }
        result['uid'] = backData;
      } else {
        result['status'] = MI_ERR;
      }
    }

    return result;
  }

  Future<List<int>> calculateCRC(List<int> pIndata) async {
    clearBitMask(DivIrqReg, 0x04);
    setBitMask(FIFOLevelReg, 0x80);

    for (int i = 0; i < pIndata.length; i++) {
      writeReg(FIFODataReg, pIndata[i]);
    }
    writeReg(CommandReg, PCD_CALCCRC);

    int i = 0xFF;
    while (true) {
      int n = readReg(DivIrqReg);
      i--;
      if (i == 0 || (n & 0x04) > 0) break;
    }

    return [readReg(CRCResultRegL), readReg(CRCResultRegM)];
  }

  Future<int> selectTag(List<int> serNum) async {
    List<int> buf = [PICC_SELECTTAG, 0x70];
    buf.addAll(serNum);

    var crc = await calculateCRC(buf);
    buf.addAll(crc);

    var result = await mfrc522ToCard(PCD_TRANSCEIVE, buf);

    if (result['status'] == MI_OK && result['backLen'] == 0x18) {
      return result['backData'][0];
    }
    return 0;
  }

  Future<int> authenticate(int authMode, int blockAddr, List<int> sectorKey,
      List<int> serNum) async {
    List<int> buff = [authMode, blockAddr];
    buff.addAll(sectorKey);
    buff.addAll(serNum.sublist(0, 4));

    var result = await mfrc522ToCard(PCD_AUTHENT, buff);

    if ((result['status'] != MI_OK) || ((readReg(Status2Reg) & 0x08) == 0)) {
      return MI_ERR;
    }

    return MI_OK;
  }

  void stopCrypto1() {
    clearBitMask(Status2Reg, 0x08);
  }

  Future<List<int>?> readTag(int blockAddr) async {
    List<int> recvData = [PICC_READ, blockAddr];
    var crc = await calculateCRC(recvData);
    recvData.addAll(crc);

    var result = await mfrc522ToCard(PCD_TRANSCEIVE, recvData);

    if (result['status'] != MI_OK) {
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
    List<int> buff = [PICC_WRITE, blockAddr];
    var crc = await calculateCRC(buff);
    buff.addAll(crc);

    var result = await mfrc522ToCard(PCD_TRANSCEIVE, buff);
    if (result['status'] != MI_OK ||
        result['backLen'] != 4 ||
        (result['backData'][0] & 0x0F) != 0x0A) {
      logger.e("Error while writing");
      return;
    }

    List<int> buf = List.from(writeData);
    crc = await calculateCRC(buf);
    buf.addAll(crc);

    result = await mfrc522ToCard(PCD_TRANSCEIVE, buf);
    if (result['status'] != MI_OK ||
        result['backLen'] != 4 ||
        (result['backData'][0] & 0x0F) != 0x0A) {
      logger.e("Error while writing");
    } else {
      logger.d("Data written successfully");
    }
  }

  void init() {
    reset();
    writeReg(TModeReg, 0x8D);
    writeReg(TPrescalerReg, 0x3E);
    writeReg(TReloadRegL, 30);
    writeReg(TReloadRegH, 0);
    writeReg(TxAutoReg, 0x40);
    writeReg(ModeReg, 0x3D);
    antennaOn();
  }

  Future<void> dumpClassic1K(List<int> key, List<int> uid) async {
    logger.d("Dumping entire MIFARE 1K card...");
    // Typically 16 sectors of 4 blocks each = 64 blocks total
    for (int blockAddr = 0; blockAddr < 64; blockAddr++) {
      // Authenticate each block with key A
      int status =
      await authenticate(Mfrc522.PICC_AUTHENT1A, blockAddr, key, uid);
      if (status == MI_OK) {
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

  @override
  void dispose() {
    spi.dispose(); // Changed from close() to dispose()
    // Only release the GPIO if we're the last instance
    if (identical(resetPin, _sharedResetPin)) {
      resetPin.release();
      _sharedResetPin = null;
    }
  }
}

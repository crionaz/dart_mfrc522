# dart_mfrc522

A Dart library for interfacing with MFRC522 RFID readers on Linux/Raspberry Pi.

## Features

- Read and write MIFARE Classic tags
- Simple high-level interface
- Configurable authentication
- Support for multiple sectors
- Hardware SPI communication

## Getting Started

```dart
import 'package:dart_mfrc522/dart_mfrc522.dart';

void main() async {
  final rfid = SimpleMfrc522();
  
  try {
    var result = await rfid.read();
    print('Card ID: ${result['id']}');
    print('Data: ${result['text']}');
  } finally {
    rfid.mfrc522.dispose();
  }
}
```

## Requirements

- Linux/Raspberry Pi
- SPI enabled
- Required permissions for SPI and GPIO access

## Installation

```yaml
dependencies:
  dart_mfrc522: ^1.0.0
```

## License

MIT

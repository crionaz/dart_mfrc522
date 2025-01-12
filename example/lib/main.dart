import 'package:flutter/material.dart';
import 'dart:async';

import 'package:mfrc522/mfrc522.dart';
import 'package:mfrc522/simple_mfrc522.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final rfid = SimpleMfrc522();
  String cardId = 'No card detected';

  @override
  void initState() {
    super.initState();
  }


  Future<String> read() async {
    try {
      var result = await rfid.read();
      if (result['id'] != null) {
        setState(() {
          cardId = 'Card ID: ${result['id']}';
        });
        return 'Card ID: ${result['id']}';
      }
    } finally {
    rfid.mfrc522.dispose();
    }
    return 'No card detected';
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('RFID Reader'),
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: ()  {
              read();
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text('Click to read card'),
                Text("Detected card: $cardId"),
              ],
            ),

          ),
        ),
      ),
    );
  }
}

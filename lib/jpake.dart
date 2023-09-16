import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

BigInt bytesToBigInt(List<int> bytes) {
  final hexString =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return BigInt.parse(hexString, radix: 16);
}

class JPAKEClient extends ChangeNotifier {
  String sharedSecret; // The shared secret is "mysecretpassword"
  List<int> primeBytes; // Byte representation of the prime

  JPAKEClient(this.sharedSecret, this.primeBytes);

  BigInt calculateSharedSecret(BigInt serverPublicKey) {
    // Convert primeBytes to a BigInt for J-PAKE
    final primeBigInt = bytesToBigInt(primeBytes);

    // Hash the shared secret and use it as the shared secret key
    final secretKey = sha256.convert(utf8.encode(sharedSecret)).bytes;

    // Simulate J-PAKE calculation by using the server's public key and prime
    return serverPublicKey.modPow(bytesToBigInt(secretKey), primeBigInt);
  }
}

void main() {
  // Replace primeBytes with your byte array representing the prime number
  final primeBytes = [
    0x00,
    0xAF,
    0x11,
    0x22,
    0x33,
    0x44,
    0x55,
    0x66,
    0x77,
    0x88,
    0x99,
    0xAA,
    0xBB,
    0xCC,
    0xDD,
    0xEE,
  ];

  final client = JPAKEClient("mysecretpassword", primeBytes);

  // Replace serverPublicKey with the actual public key received from the server
  final serverPublicKey = BigInt.from(1234567890);

  final sharedSecret = client.calculateSharedSecret(serverPublicKey);
  print("Shared Secret: $sharedSecret");
}

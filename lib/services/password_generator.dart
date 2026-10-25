import 'dart:math';

/// Random 12-character password with upper, lower, digit and symbol.
String generateTempPassword() {
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower = 'abcdefghijkmnpqrstuvwxyz';
  const digits = '23456789';
  const symbols = '!@#\$%*?';
  const all = upper + lower + digits + symbols;
  final rng = Random.secure();
  String pick(String set) => set[rng.nextInt(set.length)];
  final chars = [
    pick(upper),
    pick(lower),
    pick(digits),
    pick(symbols),
    for (var i = 0; i < 8; i++) pick(all),
  ]..shuffle(rng);
  return chars.join();
}

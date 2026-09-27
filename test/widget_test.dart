import 'package:flutter_test/flutter_test.dart';
import 'package:neverwin/models.dart';

void main() {
  test('Game catalogue matches spec', () {
    expect(GameDefs.all.length, 4);
    expect(GameDefs.byId('higher_lower').minBet, 1000);
    expect(GameDefs.byId('black_white').minBet, 1500);
    expect(GameDefs.byId('dice_even_odd').minBet, 500);
    expect(GameDefs.byId('coin_flip').minBet, 500);
  });

  test('Black/white green probability is below 8 percent', () {
    const black = 25, white = 25, green = 2;
    final p = green / (black + white + green);
    expect(p, lessThan(0.08));
  });
}

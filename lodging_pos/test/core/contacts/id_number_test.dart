import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/contacts/id_number.dart';

void main() {
  test('only the last 4 characters show', () {
    expect(maskIdNumber('12343921'), '••••3921');
    expect(maskIdNumber('AK1234567'), '••••4567');
  });

  test('4 characters or fewer are fully hidden', () {
    expect(maskIdNumber('3921'), '••••');
    expect(maskIdNumber(''), '••••');
  });
}

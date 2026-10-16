/// `••••3921`: only the last 4 characters of an ID or passport number, for
/// lists, cards and audit entries (design.md, "Mask personal data").
String maskIdNumber(String idNumber) {
  if (idNumber.length <= 4) return '••••';
  return '••••${idNumber.substring(idNumber.length - 4)}';
}

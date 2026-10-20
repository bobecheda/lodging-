Never _unsupported() =>
    throw UnsupportedError('There is no local database file on this platform.');

Future<String> defaultBackupFolder() async => _unsupported();
String joinPath(String folder, String name) => _unsupported();
Future<bool> folderExists(String folder) async => _unsupported();
Future<void> createFolder(String folder) async => _unsupported();
Future<List<String>> fileNames(String folder) async => _unsupported();
Future<int> fileSize(String path) async => _unsupported();
Future<void> deleteIfExists(String path) async => _unsupported();
Future<void> moveReplacing(String from, String to) async => _unsupported();
Future<void> copyFile(String from, String to) async => _unsupported();
String describeFileError(Object error) => '$error';
Future<String?> pickFolder() async => _unsupported();
Future<void> openFolder(String path) async => _unsupported();

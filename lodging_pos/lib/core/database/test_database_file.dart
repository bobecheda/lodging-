// Native builds get the real file operations; web gets the stub, where there
// is no local database file.
export 'test_database_file_stub.dart'
    if (dart.library.ffi) 'test_database_file_native.dart';

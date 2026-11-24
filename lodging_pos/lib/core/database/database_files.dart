// Native builds get the real file operations; web gets the stub, where there
// is no local database file.
export 'database_files_stub.dart'
    if (dart.library.ffi) 'database_files_native.dart';

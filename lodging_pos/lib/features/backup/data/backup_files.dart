// Native builds get the real file operations; web has no local database to
// back up.
export 'backup_files_stub.dart'
    if (dart.library.ffi) 'backup_files_native.dart';

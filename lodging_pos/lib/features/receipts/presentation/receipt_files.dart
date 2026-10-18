// Native builds (the Windows desk) save receipts to Documents; the web
// admin build has no file system for them.
export 'receipt_files_stub.dart'
    if (dart.library.ffi) 'receipt_files_native.dart';

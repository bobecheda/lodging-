/// Who the desk tells people to call when it refuses (story/desk-db-guards-2):
/// the one place for that text. The phone number comes from the build
/// (`SUPPORT_PHONE` in the untracked `secrets.json`), so it is never in git,
/// the audit trail or any log.
library;

const supportName = 'Bobe';

/// From `--dart-define-from-file=secrets.json`; empty in builds without it.
const supportPhone = String.fromEnvironment('SUPPORT_PHONE');

/// "call Bobe on 0722 000 000", or "call Bobe" without a number.
String get callSupport => supportPhone.isEmpty
    ? 'call $supportName'
    : 'call $supportName on $supportPhone';

/// The refusal screen's words.
String get behindRefusalText =>
    'This PC’s data is older than the cloud. Don’t use it — $callSupport.';

/// The banner's words, while someone is signed in.
String get behindBannerText =>
    'This PC’s data is older than the cloud. Finish with this guest, then '
    '$callSupport.';

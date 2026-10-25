# R8 rules for the owner's app's release build (docs/release.md). Flutter
# turns on R8 (minify and resource shrinking) for every release build.
#
# flutter_secure_storage keeps the owner's sign-in and this install's id; it
# ships no R8 rules of its own and encrypts with Google Tink, which reads its
# key protos by reflection. Keep both whole: a stripped class here would only
# show on the phone, as "signed out after every restart".
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-keepclassmembers class * extends com.google.crypto.tink.shaded.protobuf.GeneratedMessageLite {
  <fields>;
}

# Annotations Tink compiles against but doesn't ship.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn com.google.api.client.http.**
-dontwarn org.joda.time.**

# Flutter / Dart
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }

# local_auth (biometrics)
-keep class androidx.biometric.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Kotlin metadata — needed for reflection in some plugins
-keep class kotlin.Metadata { *; }

# Keep generic signatures (used by retrofit-style libs if added later)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

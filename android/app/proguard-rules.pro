# Release shrinking rules for Mobo Sales.
#
# R8 runs in full mode against proguard-android-optimize.txt, and Flutter adds
# its own flutter_proguard_rules.pro to the release build type without being
# asked. Libraries shipped as AARs carry consumer rules inside the archive,
# which AGP applies automatically. A rule belongs in this file only when
# something is reached by reflection or by name and nothing above already
# protects it.
#
# Four blanket keeps were removed on 2026-11-17. Between them they covered
# most of the DEX, which is why Play measured obfuscation at 15%:
#
#   -keep class androidx.**               { *; }
#       Redundant: the AndroidX AARs ship proguard.txt consumer rules
#       (verified in lifecycle-runtime, datastore, webkit, media3, transition).
#   -keep class com.google.android.gms.** { *; }
#       Redundant: play-services-basement and play-services-base ship consumer
#       rules carrying the keeps they actually need, such as the one on
#       BasePendingResult's members.
#   -keep class com.google.android.play.** { *; }
#       Redundant: play:review ships its own.
#   -keep class io.flutter.**             { *; }
#       Redundant: flutter_proguard_rules.pro keeps every implementation of
#       io.flutter.embedding.engine.plugins.FlutterPlugin.
#
# Two more rules were dropped as dead rather than as redundant:
#
#   The ML Kit chinese, devanagari, japanese and korean keeps. Those artifacts
#   are not on the release classpath at all — only text-recognition 16.0.1,
#   which is Latin — so the rules matched nothing. Their -dontwarn lines below
#   stay, because TextRecognizerOptions still names the absent classes.
#
#   -keepclassmembers class * { @com.google.gson.annotations.SerializedName
#   <fields>; }. Gson is not on the release classpath; this app parses JSON in
#   Dart, not in Java.

# --- Native methods --------------------------------------------------------
# JNI finds a native method by its name, so renaming one turns into an
# UnsatisfiedLinkError at runtime. Only classes that declare one are kept.
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Enums -----------------------------------------------------------------
# The platform calls values() and valueOf() reflectively when restoring an
# enum from a Bundle or a Parcel.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# --- ML Kit text recognition (business card scanning) ----------------------
# The bundled recognizer resolves its model and pipeline through ML Kit's
# internal model manager, which looks classes up by name. These packages are
# small next to the blanket keeps above, and losing the scanner is a worse
# trade than the obfuscation they cost.
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }

# Language models this app does not bundle. TextRecognizerOptions references
# them, so R8 is told not to warn about classes that are absent by design.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# --- speech_to_text --------------------------------------------------------
# Voice search reaches this plugin by name across the method channel, so
# neither the class nor its members may be renamed.
-keep class com.csdcorp.speech_to_text.** { *; }

# What R8 mustn't rename or remove in a release build. Flutter's Gradle plugin and the libraries
# (Firebase, AndroidX, the Flutter plugins) bring their own rules; these are for what this app
# looks up by name.

# The activity, the messaging service and the FileProvider are named in the manifest, which R8
# reads by itself. The bridge is one method channel handled in MainActivity, found by Flutter's
# embedding without reflection, so it needs nothing here.

# Crash reports read back through the mapping: keep the file and line numbers, under a short name.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Flutter's deferred components and the Play Core classes it mentions, which this app doesn't use.
-dontwarn com.google.android.play.core.**

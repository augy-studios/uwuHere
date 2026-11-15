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

# WorkManager (the widgets' refresh) keeps its queue in a Room database, which Room creates by
# reflection from its generated class's no-argument constructor. R8 removed that constructor in
# 2.0.0 and the app closed before it opened ("NoSuchMethodException: WorkDatabase_Impl.<init>").
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { <init>(); }
# The workers and input mergers WorkManager names in its database and creates by reflection.
-keep class * extends androidx.work.ListenableWorker { <init>(android.content.Context, androidx.work.WorkerParameters); }
-keep class * extends androidx.work.InputMerger { <init>(); }

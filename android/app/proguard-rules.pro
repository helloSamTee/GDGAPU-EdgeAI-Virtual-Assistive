# MediaPipe (used by flutter_gemma)
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Protocol Buffers
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# localagents (Gemma-specific)
-keep class com.google.ai.edge.localagents.** { *; }
-dontwarn com.google.ai.edge.localagents.**
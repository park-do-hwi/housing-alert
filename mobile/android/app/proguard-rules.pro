-keep class com.kakao.vectormap.** { *; }
-keep interface com.kakao.vectormap.**

# AdMob 이 끌어오는 WorkManager(Room) 클래스가 R8 에 지워져 앱이 시작하자마자 죽는 문제 방지
-keep class * extends androidx.room.RoomDatabase { <init>(...); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.** { *; }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

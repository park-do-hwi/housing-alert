package kr.taskcore.housing_alert

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 새 공고 알림 전용 채널(소리·팝업 켬). 서버가 보내는 FCM 알림이 이 채널로 표시된다.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                "housing_alert_new",
                "새 공고 알림",
                NotificationManager.IMPORTANCE_HIGH
            )
            ch.description = "관심 지역의 새 분양·임대 공고가 올라오면 알려드려요"
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }
}

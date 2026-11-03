package com.esurfing.esurfing_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机自启动。Application.onCreate 会拉起常驻 FlutterEngine，
 * Dart 侧再按账号的「自动连接」决定是否登录。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                SessionService.start(context, "等待自动连接")
            }
        }
    }
}

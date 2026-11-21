package com.esurfing.esurfing_app

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        (application as EsurfingApplication).flutterEngine

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        (application as EsurfingApplication).attachActivity(this)
    }

    override fun onStart() {
        (application as EsurfingApplication).startActivityHost(this)
        super.onStart()
    }

    override fun onResume() {
        super.onResume()
        (application as EsurfingApplication).resumeActivity(this)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        (application as EsurfingApplication).onWifiPermissionResult(requestCode)
    }

    override fun onPause() {
        (application as EsurfingApplication).pauseActivity(this)
        super.onPause()
    }

    override fun onStop() {
        super.onStop()
        (application as EsurfingApplication).stopActivityHost(this)
    }

    override fun onDestroy() {
        (application as EsurfingApplication).detachActivity(this)
        super.onDestroy()
    }
}

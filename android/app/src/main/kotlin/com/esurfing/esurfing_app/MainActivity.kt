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

    override fun onResume() {
        super.onResume()
        (application as EsurfingApplication).resumeActivity(this)
    }

    override fun onPause() {
        (application as EsurfingApplication).pauseActivity(this)
        super.onPause()
    }

    override fun onDestroy() {
        (application as EsurfingApplication).detachActivity(this)
        super.onDestroy()
    }
}

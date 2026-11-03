package com.esurfing.esurfing_app

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        (application as EsurfingApplication).flutterEngine

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onResume() {
        super.onResume()
        (application as EsurfingApplication).attachActivity(this)
    }

    override fun onPause() {
        (application as EsurfingApplication).detachActivity(this)
        super.onPause()
    }
}

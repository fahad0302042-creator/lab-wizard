package com.labwizard.lab_wizard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Cycles the widget speech bubble. Not exported, so another app cannot send
 * [ConsumptionBuddyWidgetProvider.ACTION_FLASKIE_TAP] and drive the widget.
 */
class FlaskieTapReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ConsumptionBuddyWidgetProvider.ACTION_FLASKIE_TAP) return
        ConsumptionBuddyWidgetProvider.cycleNextInformation(context)
    }
}

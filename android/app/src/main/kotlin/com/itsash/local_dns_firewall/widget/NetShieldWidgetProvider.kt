package com.itsash.local_dns_firewall.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.widget.RemoteViews
import com.itsash.local_dns_firewall.DnsVpnService
import com.itsash.local_dns_firewall.MainActivity
import com.itsash.local_dns_firewall.R

class NetShieldWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_TOGGLE = "com.itsash.local_dns_firewall.WIDGET_TOGGLE"
        const val EXTRA_WIDGET_IDS = "widget_ids"

        fun updateAllWidgets(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, NetShieldWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val intent = Intent(context, NetShieldWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(EXTRA_WIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) updateWidget(context, mgr, id)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, mgr: AppWidgetManager, id: Int, newOptions: android.os.Bundle
    ) {
        updateWidget(context, mgr, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TOGGLE -> {
                toggleVpn(context)
                // Refresh widget visuals after a short delay so the service state settles.
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    updateAllWidgets(context)
                }, 300)
            }
            AppWidgetManager.ACTION_APPWIDGET_UPDATE -> {
                // Handle our self-sent update broadcast with EXTRA_WIDGET_IDS.
                val ids = intent.getIntArrayExtra(EXTRA_WIDGET_IDS)
                if (ids != null) {
                    val mgr = AppWidgetManager.getInstance(context)
                    for (id in ids) updateWidget(context, mgr, id)
                }
            }
        }
    }

    private fun toggleVpn(context: Context) {
        if (DnsVpnService.running) {
            // Stop — no VPN permission needed.
            val stopIntent = Intent(context, DnsVpnService::class.java).apply {
                action = DnsVpnService.ACTION_STOP
            }
            context.startService(stopIntent)
            return
        }

        // Start — check VPN permission first.
        val prepareIntent = VpnService.prepare(context)
        if (prepareIntent != null) {
            // No prior permission. Launch MainActivity to handle the consent dialog,
            // since a BroadcastReceiver can't startActivityForResult.
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("widget_start_vpn", true)
            }
            context.startActivity(launchIntent)
            return
        }

        // Already authorised — start directly.
        val startIntent = Intent(context, DnsVpnService::class.java).apply {
            action = DnsVpnService.ACTION_START
        }
        context.startService(startIntent)
    }

    private fun updateWidget(context: Context, mgr: AppWidgetManager, widgetId: Int) {
        val isOn = DnsVpnService.running

        val views = RemoteViews(context.packageName, R.layout.widget_netshield)

        // Icon-only widget — green shield when on, gray shield when off.
        views.setInt(R.id.widget_icon, "setImageResource",
            if (isOn) R.drawable.widget_shield_on else R.drawable.widget_shield_off)

        // Toggle intent — entire widget is clickable.
        val toggleIntent = Intent(context, NetShieldWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val togglePI = PendingIntent.getBroadcast(
            context, widgetId, toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_IMMUTABLE else 0,
        )
        views.setOnClickPendingIntent(R.id.widget_icon, togglePI)

        mgr.updateAppWidget(widgetId, views)
    }
}
package com.mromrell.tunerpi.remote;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.core.content.FileProvider;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Fold-optimized companion for a private TunerPi vehicle network. */
public class MainActivity extends Activity {
    private static final int REQUEST_BT = 42;
    private static final String PI_HOST = "10.42.0.1";
    private static final String VNC_URL = "http://" + PI_HOST + ":6080/vnc.html?autoconnect=true&resize=scale";
    private static final String LOG_API = "http://" + PI_HOST + ":8088/api/logs";
    private static final String HEALTH_API = "http://" + PI_HOST + ":8088/api/health";
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private TextView status;
    private LinearLayout devices;
    private BroadcastReceiver discoveryReceiver;

    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        showHome();
        discoveryReceiver = new BroadcastReceiver() {
            @Override public void onReceive(Context context, Intent intent) {
                if (BluetoothDevice.ACTION_FOUND.equals(intent.getAction())) {
                    BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                    if (device != null) addDevice(device);
                }
            }
        };
        registerReceiver(discoveryReceiver, new IntentFilter(BluetoothDevice.ACTION_FOUND));
    }

    @Override public void onDestroy() {
        if (discoveryReceiver != null) unregisterReceiver(discoveryReceiver);
        io.shutdownNow();
        super.onDestroy();
    }

    private void showHome() {
        LinearLayout root = column(18);
        root.setBackgroundColor(Color.rgb(13, 17, 23));
        LinearLayout brand = new LinearLayout(this);
        brand.setGravity(Gravity.CENTER_VERTICAL);
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.tunerpi_roundel);
        brand.addView(logo, new LinearLayout.LayoutParams(dp(52), dp(52)));
        brand.addView(title("TUNERPI REMOTE", 28));
        root.addView(brand);
        root.addView(subtitle("Samsung Fold companion  |  Bluetooth discovery + private Wi-Fi display", 14));
        status = subtitle("Connect the Fold to TunerPi-AA Wi-Fi, then select a function.", 15);
        status.setTextColor(Color.rgb(145, 202, 255));
        root.addView(status);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(isExpanded() ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        actions.setPadding(0, 26, 0, 12);
        actions.addView(actionButton("CHECK PI", "Verify connection", this::checkPi), actionParams());
        actions.addView(actionButton("DISCOVER PI", "Pair over Bluetooth", this::discover), actionParams());
        actions.addView(actionButton("VIEW DISPLAY", "Live Pi touch display", this::showDisplay), actionParams());
        actions.addView(actionButton("ECU LOGS", "Download and share files", this::loadLogs), actionParams());
        root.addView(actions);

        devices = column(0);
        root.addView(devices);
        root.addView(subtitle("Bluetooth identifies the Pi. Display and file transfer use Wi-Fi for the bandwidth needed by live video.", 13));
        setContentView(root);
    }

    private void discover() {
        if (!hasBluetoothPermission()) return;
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) { setStatus("This phone has no Bluetooth adapter."); return; }
        if (!adapter.isEnabled()) { startActivity(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)); return; }
        devices.removeAllViews();
        setStatus("Scanning for TunerPi over Bluetooth…");
        adapter.cancelDiscovery();
        adapter.startDiscovery();
    }

    private boolean hasBluetoothPermission() {
        if (Build.VERSION.SDK_INT >= 31 && checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT}, REQUEST_BT);
            return false;
        }
        return true;
    }

    private void addDevice(BluetoothDevice device) {
        String name = device.getName() == null ? "Unnamed Bluetooth device" : device.getName();
        if (!name.toLowerCase().contains("tuner") && !name.toLowerCase().contains("bmw")) return;
        Button item = actionButton(name, device.getAddress(), () -> {
            if (Build.VERSION.SDK_INT >= 31 && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return;
            device.createBond();
            setStatus("Pairing requested. Keep the Fold connected to TunerPi-AA Wi-Fi for display and logs.");
        });
        devices.addView(item);
    }

    private void showDisplay() {
        WebView display = new WebView(this);
        WebSettings settings = display.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        display.setWebViewClient(new WebViewClient());
        display.loadUrl(VNC_URL);
        setContentView(display);
    }

    private void checkPi() {
        setStatus("Checking Pi connection...");
        io.execute(() -> {
            try {
                JSONObject health = new JSONObject(readText(HEALTH_API));
                JSONObject services = health.getJSONObject("services");
                JSONObject bluetooth = health.getJSONObject("bluetooth");
                boolean ready = "active".equals(services.optString("tunerpi-logs-api.service"))
                        && "active".equals(services.optString("crankshaft-core.service"));
                String message = ready
                        ? "Pi ready: " + bluetooth.optString("alias") + "."
                        : "Pi reachable, but setup is still finishing. Try again shortly.";
                runOnUiThread(() -> setStatus(message));
            } catch (Exception error) {
                runOnUiThread(() -> setStatus("Pi not reachable. Join TunerPi-AA Wi-Fi, then retry."));
            }
        });
    }

    private void loadLogs() {
        setStatus("Fetching ECU logs…");
        io.execute(() -> {
            try {
                JSONArray logs = new JSONArray(readText(LOG_API));
                runOnUiThread(() -> showLogs(logs));
            } catch (Exception error) {
                runOnUiThread(() -> setStatus("Could not reach Pi logs. Join TunerPi-AA Wi-Fi and verify the Pi is running."));
            }
        });
    }

    private void showLogs(JSONArray logs) {
        LinearLayout list = column(16);
        list.setBackgroundColor(Color.rgb(13, 17, 23));
        Button back = actionButton("‹ BACK", "TunerPi home", this::showHome);
        list.addView(back);
        list.addView(title("ECU LOGS", 26));
        for (int i = 0; i < logs.length(); i++) {
            JSONObject log = logs.optJSONObject(i);
            if (log == null) continue;
            String name = log.optString("name");
            String info = log.optString("size") + " bytes  |  " + log.optString("modified");
            list.addView(actionButton(name, "Download and share • " + info, () -> downloadAndShare(name, log.optString("url"))));
        }
        ScrollView scroll = new ScrollView(this);
        scroll.addView(list);
        setContentView(scroll);
    }

    private void downloadAndShare(String name, String url) {
        Toast.makeText(this, "Downloading " + name, Toast.LENGTH_SHORT).show();
        io.execute(() -> {
            try {
                File directory = new File(getCacheDir(), "downloads");
                directory.mkdirs();
                File file = new File(directory, name.replaceAll("[^A-Za-z0-9._-]", "_"));
                HttpURLConnection connection = (HttpURLConnection) new URL("http://" + PI_HOST + ":8088" + url).openConnection();
                try (InputStream input = connection.getInputStream(); FileOutputStream output = new FileOutputStream(file)) {
                    byte[] buffer = new byte[32768]; int count;
                    while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                }
                Uri content = FileProvider.getUriForFile(this, getPackageName() + ".files", file);
                Intent share = new Intent(Intent.ACTION_SEND).setType("application/octet-stream").putExtra(Intent.EXTRA_STREAM, content).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                runOnUiThread(() -> startActivity(Intent.createChooser(share, "Share ECU log")));
            } catch (Exception error) {
                runOnUiThread(() -> Toast.makeText(this, "Log download failed", Toast.LENGTH_LONG).show());
            }
        });
    }

    private String readText(String url) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(5000); connection.setReadTimeout(5000);
        try (InputStream input = connection.getInputStream()) {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192]; int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            return output.toString("UTF-8");
        }
    }

    private void setStatus(String message) { if (status != null) status.setText(message); }
    private boolean isExpanded() { return getResources().getConfiguration().screenWidthDp >= 600; }
    private LinearLayout column(int padding) { LinearLayout view = new LinearLayout(this); view.setOrientation(LinearLayout.VERTICAL); view.setPadding(padding, padding, padding, padding); return view; }
    private TextView title(String value, int size) { TextView view = new TextView(this); view.setText(value); view.setTextSize(size); view.setTextColor(Color.WHITE); view.setPadding(0, 8, 0, 8); return view; }
    private TextView subtitle(String value, int size) { TextView view = title(value, size); view.setTextColor(Color.rgb(177, 190, 205)); return view; }
    private Button actionButton(String label, String detail, Runnable action) { Button button = new Button(this); button.setAllCaps(false); button.setText(label + "\n" + detail); button.setTextSize(16); button.setGravity(Gravity.CENTER); button.setOnClickListener(v -> action.run()); button.setPadding(12, 24, 12, 24); return button; }
    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density + 0.5f); }
    private LinearLayout.LayoutParams actionParams() {
        return isExpanded()
                ? new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                : new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
    }
}

package jp.hossie.osmo360_shutter_app

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlertDialog
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.*
import android.location.*
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.*
import android.speech.tts.TextToSpeech
import android.util.AtomicFile
import android.view.View
import android.view.WindowManager
import android.webkit.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.*
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.math.sqrt

@SuppressLint("MissingPermission")
class MainActivity : FlutterActivity(), SensorEventListener, LocationListener {
    private val handler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var gatt: BluetoothGatt? = null
    private var tx: BluetoothGattCharacteristic? = null
    private var selected: BluetoothDevice? = null
    private var connectResult: MethodChannel.Result? = null
    private var writeResult: MethodChannel.Result? = null
    private var chunks = ArrayDeque<ByteArray>()
    private var mtu = 23
    private var scanCallback: ScanCallback? = null
    private var permissionAction: (() -> Unit)? = null
    private var permissionFailure: (() -> Unit)? = null
    private var permissionMandatory = true
    private lateinit var sensors: SensorManager
    private lateinit var locations: LocationManager
    private var sensorsRunning = false
    private var lastLinear = 0.0
    private var lastGyro = 0.0
    private var linearAt = 0L
    private var gyroAt = 0L
    private var lastMotionAt = 0L
    private var satellites = 0
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var tone: ToneGenerator? = null
    private var exportResult: MethodChannel.Result? = null
    private var exportContent = ""
    private val serviceId = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
    private val rxId = UUID.fromString("0000fff4-0000-1000-8000-00805f9b34fb")
    private val txId = UUID.fromString("0000fff5-0000-1000-8000-00805f9b34fb")
    private val cccdId = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    private val adapter get() = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private val connectTimeout = Runnable { failConnection("Bluetooth接続がタイムアウトしました") }
    private val writeTimeout = Runnable { failConnection("BLE書き込みがタイムアウトしました。再送していません") }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        locations = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        tts = TextToSpeech(this) { status -> ttsReady = status == TextToSpeech.SUCCESS; if (ttsReady) tts?.language = Locale.JAPANESE }
        tone = ToneGenerator(AudioManager.STREAM_MUSIC, 35)
        EventChannel(engine.dartExecutor.binaryMessenger, "osmo360/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) { events = sink }
            override fun onCancel(args: Any?) { events = null }
        })
        MethodChannel(engine.dartExecutor.binaryMessenger, "osmo360/device").setMethodCallHandler { call, result ->
            try { dispatch(call, result) } catch (e: Exception) { result.error("DEVICE", e.message, null) }
        }
        engine.platformViewsController.registry.registerViewFactory("osmo360/map", MapFactory(engine.dartExecutor.binaryMessenger))
    }
    private fun emit(type: String, data: Map<String, Any?> = emptyMap()) {
        handler.post { events?.success(mapOf("type" to type) + data) }
    }
    private fun has(permission: String) = Build.VERSION.SDK_INT < 23 || checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    private fun permissions(list: List<String>, result: MethodChannel.Result, mandatory: Boolean = true, action: () -> Unit) {
        val needed = list.filter { !has(it) }
        if (needed.isEmpty()) { action(); return }
        if (permissionAction != null) { result.error("BUSY", "許可ダイアログを確認してください", null); return }
        permissionAction = action; permissionFailure = { result.error("PERMISSION", "Bluetoothの許可が必要です", null) }
        permissionMandatory = mandatory
        requestPermissions(needed.toTypedArray(), 401)
    }
    override fun onRequestPermissionsResult(code: Int, names: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, names, results)
        if (code != 401) return
        val action = permissionAction; val failure = permissionFailure; val mandatory = permissionMandatory
        permissionAction = null; permissionFailure = null
        if (!mandatory || (results.isNotEmpty() && results.all { it == PackageManager.PERMISSION_GRANTED })) action?.invoke() else failure?.invoke()
    }
    private fun capabilities(): Map<String, Any?> = mapOf(
        "platform" to "android", "bluetooth" to (adapter != null), "location" to true,
        "motion" to (sensors.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION) != null && sensors.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null),
        "nativeSteps" to (sensors.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) != null && (Build.VERSION.SDK_INT < 29 || has(Manifest.permission.ACTIVITY_RECOGNITION))),
        "wakeLock" to true, "install" to false)
    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(capabilities())
            "connect" -> permissions(if (Build.VERSION.SDK_INT >= 31) listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT) else listOf(Manifest.permission.ACCESS_FINE_LOCATION), result) {
                connect(call.argument<Boolean>("reconnect") == true, result)
            }
            "disconnect" -> { disconnect(); result.success(null) }
            "write" -> write(call.argument<List<Int>>("bytes") ?: emptyList(), result)
            "startSensors" -> permissions(listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION) + if (Build.VERSION.SDK_INT >= 29) listOf(Manifest.permission.ACTIVITY_RECOGNITION) else emptyList(), result, false) { startSensors(); result.success(null) }
            "stopSensors" -> { stopSensors(); result.success(null) }
            "keepAwake" -> { window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); result.success(null) }
            "feedback" -> {
                if (call.argument<Boolean>("sound") == true) tone?.startTone(ToneGenerator.TONE_PROP_BEEP, 100)
                if (call.argument<Boolean>("voice") == true && ttsReady) tts?.speak(call.argument<String>("text") ?: "", TextToSpeech.QUEUE_FLUSH, null, "osmo-notice")
                if (call.argument<Boolean>("vibrate") == true) {
                    val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                    if (Build.VERSION.SDK_INT >= 26) vibrator.vibrate(VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE)) else @Suppress("DEPRECATION") vibrator.vibrate(60)
                }
                result.success(null)
            }
            "load", "save", "remove" -> {
                val key = call.argument<String>("key") ?: throw IllegalArgumentException("key required")
                require(Regex("[A-Za-z0-9_-]{1,64}").matches(key))
                val file = AtomicFile(File(filesDir, "osmo-$key.json"))
                when (call.method) {
                    "load" -> result.success(if (file.baseFile.exists()) file.openRead().bufferedReader().use { it.readText() } else null)
                    "remove" -> { file.delete(); result.success(null) }
                    else -> {
                        val stream = file.startWrite()
                        try { stream.write((call.argument<String>("value") ?: "").toByteArray(Charsets.UTF_8)); file.finishWrite(stream) }
                        catch (e: Exception) { file.failWrite(stream); throw e }
                        result.success(null)
                    }
                }
            }
            "export" -> {
                if (exportResult != null) { result.error("BUSY", "書き出し中です", null); return }
                exportResult = result; exportContent = call.argument<String>("content") ?: ""
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE); type = call.argument<String>("mime") ?: "application/json"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "osmo360.json")
                }
                @Suppress("DEPRECATION") startActivityForResult(intent, 402)
            }
            "install" -> result.success(mapOf("hint" to "Androidアプリとしてインストール済みです"))
            else -> result.notImplemented()
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 402) return
        val result = exportResult; exportResult = null
        try {
            if (resultCode == RESULT_OK && data?.data != null) {
                val stream = contentResolver.openOutputStream(data.data!!) ?: throw IllegalStateException("保存先を開けません")
                stream.use { it.write(exportContent.toByteArray(Charsets.UTF_8)) }
                result?.success(null)
            } else result?.error("CANCELLED", "書き出しをキャンセルしました", null)
        } catch (e: Exception) { result?.error("EXPORT", e.message, null) }
        exportContent = ""
    }
    private fun connect(reconnect: Boolean, result: MethodChannel.Result) {
        if (connectResult != null) { result.error("BUSY", "接続処理中です", null); return }
        if (adapter == null || !adapter.isEnabled) { result.error("BLUETOOTH", "端末のBluetoothをONにしてください", null); return }
        disconnect(); connectResult = result
        if (reconnect && selected != null) { connectDevice(selected!!); return }
        val found = linkedMapOf<String, BluetoothDevice>()
        val scanner = adapter.bluetoothLeScanner ?: run { failConnection("BLEスキャナーを利用できません"); return }
        val callback = object : ScanCallback() {
            override fun onScanResult(type: Int, scan: ScanResult) {
                val name = scan.device.name ?: scan.scanRecord?.deviceName ?: return
                if (name.contains("Osmo", true) || name.contains("DJI", true)) found[scan.device.address] = scan.device
            }
            override fun onScanFailed(error: Int) { handler.post { failConnection("BLE検索エラー $error") } }
        }
        scanCallback = callback
        scanner.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
        handler.postDelayed({
            if (scanCallback !== callback) return@postDelayed
            scanner.stopScan(callback); scanCallback = null
            if (found.isEmpty()) { failConnection("カメラが見つかりません。電源とBluetoothを確認してください"); return@postDelayed }
            val devices = found.values.toList()
            AlertDialog.Builder(this).setTitle("接続するOsmoカメラ")
                .setItems(devices.map { "${it.name ?: "Osmo"}  ${it.address.takeLast(5)}" }.toTypedArray()) { _, index -> connectDevice(devices[index]) }
                .setOnCancelListener { failConnection("接続をキャンセルしました") }.show()
        }, 6500)
    }
    private fun connectDevice(device: BluetoothDevice) {
        selected = device; mtu = 23
        handler.postDelayed(connectTimeout, 30000)
        gatt = device.connectGatt(this, false, callback, BluetoothDevice.TRANSPORT_LE)
    }
    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, state: Int) { handler.post {
            if (g !== gatt) return@post
            if (status != BluetoothGatt.GATT_SUCCESS || state == BluetoothProfile.STATE_DISCONNECTED) { failConnection("BLE切断 ($status)"); return@post }
            if (state == BluetoothProfile.STATE_CONNECTED) {
                if (!g.requestMtu(185)) g.discoverServices()
            }
        } }
        override fun onMtuChanged(g: BluetoothGatt, value: Int, status: Int) { handler.post {
            if (g !== gatt) return@post
            if (status == BluetoothGatt.GATT_SUCCESS) mtu = value
            g.discoverServices()
        } }
        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) { handler.post {
            if (g !== gatt) return@post
            if (status != BluetoothGatt.GATT_SUCCESS) { failConnection("GATTサービス取得に失敗"); return@post }
            val service = g.getService(serviceId)
            val rx = service?.getCharacteristic(rxId); tx = service?.getCharacteristic(txId)
            val descriptor = rx?.getDescriptor(cccdId)
            if (rx == null || tx == null || descriptor == null || !g.setCharacteristicNotification(rx, true)) { failConnection("OsmoのFFF0/FFF4/FFF5が見つかりません"); return@post }
            val success = if (Build.VERSION.SDK_INT >= 33) g.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothStatusCodes.SUCCESS else {
                @Suppress("DEPRECATION") descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION") g.writeDescriptor(descriptor)
            }
            if (!success) failConnection("通知購読を開始できません")
        } }
        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) { handler.post {
            if (g !== gatt) return@post
            if (status != BluetoothGatt.GATT_SUCCESS) { failConnection("通知購読に失敗"); return@post }
            handler.removeCallbacks(connectTimeout)
            val name = g.device.name ?: "Osmo 360"
            emit("connected", mapOf("name" to name, "mtu" to mtu))
            connectResult?.success(mapOf("name" to name)); connectResult = null
        } }
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) { if (g === gatt && characteristic.uuid == rxId) emit("bytes", mapOf("bytes" to value.map { it.toInt() and 255 })) }
        @Deprecated("Legacy Android callback")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION") val value = characteristic.value ?: return
            if (g === gatt && characteristic.uuid == rxId) emit("bytes", mapOf("bytes" to value.map { it.toInt() and 255 }))
        }
        override fun onCharacteristicWrite(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) { handler.post {
            if (g !== gatt) return@post
            if (status != BluetoothGatt.GATT_SUCCESS) { failConnection("BLE書き込みエラー $status。再送していません"); return@post }
            writeNext()
        } }
    }
    private fun write(bytes: List<Int>, result: MethodChannel.Result) {
        if (writeResult != null) { result.error("BUSY", "BLE送信中です", null); return }
        if (gatt == null || tx == null) { result.error("DISCONNECTED", "カメラ未接続", null); return }
        require(bytes.size <= 1023)
        writeResult = result; chunks = ArrayDeque(bytes.chunked((mtu - 3).coerceAtLeast(20)).map { part -> part.map { it.toByte() }.toByteArray() })
        handler.postDelayed(writeTimeout, 3500); writeNext()
    }
    private fun writeNext() {
        if (chunks.isEmpty()) { handler.removeCallbacks(writeTimeout); writeResult?.success(null); writeResult = null; return }
        val data = chunks.removeFirst(); val characteristic = tx ?: return; val g = gatt ?: return
        val type = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        val success = if (Build.VERSION.SDK_INT >= 33) g.writeCharacteristic(characteristic, data, type) == BluetoothStatusCodes.SUCCESS else {
            characteristic.writeType = type
            @Suppress("DEPRECATION") characteristic.value = data
            @Suppress("DEPRECATION") g.writeCharacteristic(characteristic)
        }
        if (!success) failConnection("BLE書き込みを開始できません。再送していません")
    }
    private fun failConnection(message: String) {
        connectResult?.error("CONNECTION", message, null); connectResult = null
        writeResult?.error("WRITE", message, null); writeResult = null
        disconnect(); emit("error", mapOf("source" to "ble", "message" to message))
    }
    private fun disconnect() {
        scanCallback?.let { adapter?.bluetoothLeScanner?.stopScan(it) }; scanCallback = null
        handler.removeCallbacks(connectTimeout); handler.removeCallbacks(writeTimeout)
        val old = gatt; gatt = null; tx = null; chunks.clear()
        old?.disconnect(); old?.close()
        writeResult?.error("DISCONNECTED", "接続が切断されました", null); writeResult = null
        if (old != null) emit("disconnected")
    }
    private val gnss = object : GnssStatus.Callback() { override fun onSatelliteStatusChanged(status: GnssStatus) { satellites = (0 until status.satelliteCount).count { status.usedInFix(it) } } }
    private fun startSensors() {
        if (sensorsRunning) { window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); return }
        sensorsRunning = true; linearAt = 0; gyroAt = 0
        listOf(Sensor.TYPE_LINEAR_ACCELERATION, Sensor.TYPE_GYROSCOPE).forEach { type -> sensors.getDefaultSensor(type)?.let { sensors.registerListener(this, it, 20000) } }
        if (capabilities()["nativeSteps"] == true) sensors.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)?.let { sensors.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
        if (has(Manifest.permission.ACCESS_FINE_LOCATION) || has(Manifest.permission.ACCESS_COARSE_LOCATION)) {
            for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                try { if (locations.isProviderEnabled(provider)) locations.requestLocationUpdates(provider, 1000, 0f, this, Looper.getMainLooper()) }
                catch (e: Exception) { emit("warning", mapOf("message" to "測位プロバイダー: ${e.message}")) }
            }
            if (Build.VERSION.SDK_INT >= 24 && has(Manifest.permission.ACCESS_FINE_LOCATION)) locations.registerGnssStatusCallback(gnss, handler)
            if (!locations.isProviderEnabled(LocationManager.GPS_PROVIDER)) emit("error", mapOf("source" to "gps", "message" to "端末の位置情報をONにしてください"))
        } else emit("error", mapOf("source" to "gps", "message" to "位置情報の許可がありません"))
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        emit("capabilities", capabilities())
    }
    private fun stopSensors() {
        sensors.unregisterListener(this); locations.removeUpdates(this)
        if (Build.VERSION.SDK_INT >= 24) locations.unregisterGnssStatusCallback(gnss)
        sensorsRunning = false; window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); tts?.stop()
    }
    override fun onSensorChanged(event: SensorEvent) {
        if (!sensorsRunning) return
        when (event.sensor.type) {
            Sensor.TYPE_STEP_DETECTOR -> { emit("step"); return }
            Sensor.TYPE_LINEAR_ACCELERATION -> { lastLinear = norm(event.values); linearAt = event.timestamp }
            Sensor.TYPE_GYROSCOPE -> { lastGyro = norm(event.values); gyroAt = event.timestamp }
        }
        val now = SystemClock.elapsedRealtimeNanos()
        if (now - linearAt < 200000000 && now - gyroAt < 200000000 && now - lastMotionAt > 20000000) {
            lastMotionAt = now; emit("motion", mapOf("linear" to lastLinear, "gyro" to lastGyro))
        }
    }
    private fun norm(a: FloatArray) = sqrt(a.take(3).sumOf { it.toDouble() * it.toDouble() })
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onLocationChanged(location: Location) {
        // Reject provider-cached fixes using the independent monotonic timestamp.
        if (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos > 15000000000L) return
        emit("location", mapOf("lat" to location.latitude, "lon" to location.longitude, "accuracy" to location.accuracy,
            "timestamp" to location.time, "altitude" to if (location.hasAltitude()) location.altitude else null,
            "verticalAccuracy" to if (Build.VERSION.SDK_INT >= 26 && location.hasVerticalAccuracy()) location.verticalAccuracyMeters else null,
            "speed" to if (location.hasSpeed()) location.speed else null, "heading" to if (location.hasBearing()) location.bearing else null,
            "speedAccuracy" to if (Build.VERSION.SDK_INT >= 26 && location.hasSpeedAccuracy()) location.speedAccuracyMetersPerSecond else null,
            "satellites" to if (location.provider == LocationManager.GPS_PROVIDER) satellites else 0,
            "altitudeReference" to "WGS84 ellipsoid (Android)"))
    }
    override fun onProviderDisabled(provider: String) { emit("error", mapOf("source" to "gps", "message" to "位置情報が停止しました")) }
    override fun onProviderEnabled(provider: String) {}
    @Deprecated("Legacy location callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    override fun onPause() { emit("visibility", mapOf("visible" to false)); if (::sensors.isInitialized) stopSensors(); super.onPause() }
    override fun onResume() { super.onResume(); emit("visibility", mapOf("visible" to true)) }
    override fun onDestroy() { if (::sensors.isInitialized) stopSensors(); disconnect(); tts?.shutdown(); tone?.release(); super.onDestroy() }
}

class MapFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView = MapView(context, messenger, id, args as? Map<*, *> ?: emptyMap<Any, Any>())
}
@SuppressLint("SetJavaScriptEnabled")
class MapView(context: Context, messenger: BinaryMessenger, id: Int, initial: Map<*, *>) : PlatformView {
    private val web = WebView(context)
    private val channel = MethodChannel(messenger, "osmo360/map/$id")
    private var config = JSONObject(initial).toString()
    private var ready = false
    init {
        web.settings.javaScriptEnabled = true
        web.settings.allowFileAccess = false; web.settings.allowContentAccess = false
        web.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        web.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) { ready = true; update() }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true
        }
        web.loadDataWithBaseURL("https://hossie-jp.github.io/osmo360-shutter-app/", context.assets.open("map.html").bufferedReader().use { it.readText() }, "text/html", "UTF-8", null)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "update") { config = JSONObject(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()).toString(); update(); result.success(null) } else result.notImplemented()
        }
    }
    private fun update() { if (ready) web.evaluateJavascript("window.osmoSetMapConfig($config)", null) }
    override fun getView(): View = web
    override fun dispose() { channel.setMethodCallHandler(null); web.destroy() }
}

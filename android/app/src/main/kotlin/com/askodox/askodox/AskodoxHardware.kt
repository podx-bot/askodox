package com.askodox.askodox

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Shop hardware + phone sensors on their OWN channel ("com.askodox.app/hardware") so the
 * device channel and the OTP SMS-consent code in MainActivity are untouched.
 *
 *  - Classic Bluetooth (SPP / RFCOMM) receipt printers: bonded devices + raw ESC/POS bytes.
 *  - USB receipt printers (USB host, bulk OUT endpoint): device list + raw bytes.
 *  - Light sensor (lux) and microphone level (dBFS, uncalibrated) for the Smart Tools meters.
 *
 * Nothing here claims a printer model works: each call reports exactly what the radio / USB
 * stack answered. Blocking I/O runs on a background thread; results return on the main thread.
 */
object AskodoxHardware {
    private const val CHANNEL = "com.askodox.app/hardware"
    private const val USB_PERMISSION = "com.askodox.askodox.USB_PERMISSION"
    private const val BT_PERMISSION_REQUEST = 4311
    private const val MIC_PERMISSION_REQUEST = 4312
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val main = Handler(Looper.getMainLooper())

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "bondedPrinters" -> bondedPrinters(activity, result)
                "sendClassic" -> sendClassic(activity, call.argument("address"), call.argument("bytes"), result)
                "usbPrinters" -> usbPrinters(activity, result)
                "sendUsb" -> sendUsb(activity, call.argument("device"), call.argument("bytes"), result)
                "lightLevel" -> lightLevel(activity, result)
                "soundLevel" -> soundLevel(activity, call.argument<Int>("millis") ?: 600, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun reply(block: () -> Unit) = main.post(block)

    private fun btConnectGranted(activity: Activity): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun adapter(activity: Activity): BluetoothAdapter? =
        (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    @SuppressLint("MissingPermission")
    private fun bondedPrinters(activity: Activity, result: MethodChannel.Result) {
        if (!btConnectGranted(activity)) {
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.BLUETOOTH_CONNECT), BT_PERMISSION_REQUEST)
            result.error("permission_requested", "Allow Nearby devices, then try again", null)
            return
        }
        val bt = adapter(activity)
        if (bt == null) {
            result.error("no_bluetooth", "This phone has no Bluetooth", null)
            return
        }
        if (!bt.isEnabled) {
            result.error("bluetooth_off", "Bluetooth is off", null)
            return
        }
        val rows = bt.bondedDevices.orEmpty().map { d ->
            mapOf(
                "address" to d.address,
                "name" to (d.name ?: ""),
                // 0x0600 = imaging major class (printers usually report it, many cheap ones do not)
                "imaging" to ((d.bluetoothClass?.majorDeviceClass ?: 0) == 0x0600),
            )
        }
        result.success(rows)
    }

    @SuppressLint("MissingPermission")
    private fun sendClassic(activity: Activity, address: String?, bytes: ByteArray?, result: MethodChannel.Result) {
        if (address.isNullOrBlank() || bytes == null || bytes.isEmpty()) {
            result.error("bad_request", "Printer address and bytes are required", null)
            return
        }
        if (!btConnectGranted(activity)) {
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.BLUETOOTH_CONNECT), BT_PERMISSION_REQUEST)
            result.error("permission_requested", "Allow Nearby devices, then try again", null)
            return
        }
        val bt = adapter(activity)
        if (bt == null || !bt.isEnabled) {
            result.error("bluetooth_off", "Bluetooth is off", null)
            return
        }
        Thread {
            try {
                val device = bt.getRemoteDevice(address)
                try {
                    bt.cancelDiscovery()
                } catch (_: Exception) {
                }
                device.createRfcommSocketToServiceRecord(SPP_UUID).use { socket ->
                    socket.connect()
                    val out = socket.outputStream
                    var i = 0
                    while (i < bytes.size) {
                        val end = minOf(i + 512, bytes.size)
                        out.write(bytes, i, end - i)
                        out.flush()
                        i = end
                    }
                    // Let the printer drain its buffer before the link closes.
                    Thread.sleep(400)
                }
                reply { result.success(true) }
            } catch (e: Exception) {
                reply { result.error("send_failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }.start()
    }

    private fun usbManager(activity: Activity): UsbManager? = activity.getSystemService(Context.USB_SERVICE) as? UsbManager

    private fun bulkOut(device: UsbDevice): Pair<Int, Int>? {
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            for (e in 0 until iface.endpointCount) {
                val ep = iface.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) {
                    return Pair(i, e)
                }
            }
        }
        return null
    }

    private fun usbPrinters(activity: Activity, result: MethodChannel.Result) {
        val usb = usbManager(activity)
        if (usb == null) {
            result.success(emptyList<Any>())
            return
        }
        val rows = usb.deviceList.values.filter { bulkOut(it) != null }.map { d ->
            val printerClass = (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_PRINTER }
            mapOf(
                "device" to d.deviceName,
                "name" to listOfNotNull(d.manufacturerName, d.productName).joinToString(" ").ifBlank { d.deviceName },
                "vendorId" to d.vendorId,
                "productId" to d.productId,
                "printerClass" to printerClass,
                "permission" to usb.hasPermission(d),
            )
        }
        result.success(rows)
    }

    private fun sendUsb(activity: Activity, deviceName: String?, bytes: ByteArray?, result: MethodChannel.Result) {
        val usb = usbManager(activity)
        val device = usb?.deviceList?.get(deviceName ?: "")
        if (usb == null || device == null || bytes == null || bytes.isEmpty()) {
            result.error("not_found", "USB printer not connected", null)
            return
        }
        if (!usb.hasPermission(device)) {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val intent = PendingIntent.getBroadcast(activity, 0, Intent(USB_PERMISSION).setPackage(activity.packageName), flags)
            usb.requestPermission(device, intent)
            result.error("permission_requested", "Allow the USB printer, then try again", null)
            return
        }
        val endpoint = bulkOut(device)
        if (endpoint == null) {
            result.error("no_endpoint", "This USB device has no print channel", null)
            return
        }
        Thread {
            try {
                val connection = usb.openDevice(device) ?: throw IllegalStateException("Could not open the USB device")
                try {
                    val iface = device.getInterface(endpoint.first)
                    if (!connection.claimInterface(iface, true)) throw IllegalStateException("USB interface busy")
                    val ep = iface.getEndpoint(endpoint.second)
                    var i = 0
                    while (i < bytes.size) {
                        val len = minOf(4096, bytes.size - i)
                        val sent = connection.bulkTransfer(ep, bytes, i, len, 5000)
                        if (sent <= 0) throw IllegalStateException("USB write failed")
                        i += sent
                    }
                    connection.releaseInterface(iface)
                } finally {
                    connection.close()
                }
                reply { result.success(true) }
            } catch (e: Exception) {
                reply { result.error("send_failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }.start()
    }

    private fun lightLevel(activity: Activity, result: MethodChannel.Result) {
        val sensors = activity.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val light = sensors?.getDefaultSensor(Sensor.TYPE_LIGHT)
        if (sensors == null || light == null) {
            result.error("no_sensor", "This phone has no light sensor", null)
            return
        }
        var done = false
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (done) return
                done = true
                sensors.unregisterListener(this)
                result.success(event.values.firstOrNull()?.toDouble() ?: 0.0)
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensors.registerListener(listener, light, SensorManager.SENSOR_DELAY_UI)
        main.postDelayed({
            if (!done) {
                done = true
                sensors.unregisterListener(listener)
                result.error("no_reading", "The light sensor sent no reading", null)
            }
        }, 3000)
    }

    @SuppressLint("MissingPermission")
    private fun soundLevel(activity: Activity, millis: Int, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.RECORD_AUDIO), MIC_PERMISSION_REQUEST)
            result.error("permission_requested", "Allow the microphone, then try again", null)
            return
        }
        Thread {
            var recorder: AudioRecord? = null
            try {
                val rate = 44100
                val minBuffer = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                if (minBuffer <= 0) throw IllegalStateException("Microphone unavailable")
                recorder = AudioRecord(MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, minBuffer * 2)
                if (recorder.state != AudioRecord.STATE_INITIALIZED) throw IllegalStateException("Microphone busy")
                recorder.startRecording()
                val buffer = ShortArray(minBuffer)
                val wanted = rate * millis.coerceIn(200, 3000) / 1000
                var count = 0L
                var sumSquares = 0.0
                var peak = 0
                while (count < wanted) {
                    val n = recorder.read(buffer, 0, buffer.size)
                    if (n <= 0) break
                    for (k in 0 until n) {
                        val v = buffer[k].toInt()
                        sumSquares += v.toDouble() * v
                        if (kotlin.math.abs(v) > peak) peak = kotlin.math.abs(v)
                    }
                    count += n
                }
                if (count == 0L) throw IllegalStateException("No audio")
                val rms = sqrt(sumSquares / count)
                val dbfs = if (rms < 1.0) -90.0 else 20 * log10(rms / 32768.0)
                val peakDbfs = if (peak < 1) -90.0 else 20 * log10(peak / 32768.0)
                reply { result.success(mapOf("dbfs" to dbfs, "peak_dbfs" to peakDbfs)) }
            } catch (e: Exception) {
                reply { result.error("no_reading", e.message ?: e.javaClass.simpleName, null) }
            } finally {
                try {
                    recorder?.stop()
                } catch (_: Exception) {
                }
                recorder?.release()
            }
        }.start()
    }
}

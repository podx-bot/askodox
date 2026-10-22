/// Bluetooth SIG standard GATT services / characteristics ASKODOX reads, and
/// their decoders (pure, unit-tested). Source: Bluetooth SIG Assigned
/// Numbers and the GATT Specification Supplement. A device that uses a
/// private protocol instead of these standards shows no reading -- never a
/// made-up one.
library;

/// 16-bit SIG UUID (lower-case hex) from a 16- or 128-bit UUID string.
String? askodoxShortUuid(String uuid) {
  final u = uuid.trim().toLowerCase();
  if (RegExp(r'^[0-9a-f]{4}$').hasMatch(u)) return u;
  final m = RegExp(r'^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$').firstMatch(u);
  return m?.group(1);
}

class AskodoxBleProfile {
  const AskodoxBleProfile(this.service, this.characteristic, this.kind, this.nameEn, this.nameTe);
  final String service;
  final String characteristic;
  final String kind; // weight | temperature | humidity | heart_rate | battery
  final String nameEn;
  final String nameTe;
}

const askodoxBleProfiles = <AskodoxBleProfile>[
  AskodoxBleProfile('181d', '2a9d', 'weight', 'Weight scale', 'తూకం యంత్రం'),
  AskodoxBleProfile('181a', '2a6e', 'temperature', 'Temperature', 'ఉష్ణోగ్రత'),
  AskodoxBleProfile('181a', '2a6f', 'humidity', 'Humidity', 'తేమ'),
  AskodoxBleProfile('1809', '2a1c', 'temperature', 'Thermometer', 'థర్మామీటర్'),
  AskodoxBleProfile('180d', '2a37', 'heart_rate', 'Heart rate', 'హృదయ స్పందన'),
  AskodoxBleProfile('180f', '2a19', 'battery', 'Battery', 'బ్యాటరీ'),
];

/// Profiles a device offers, from its (advertised or discovered) services.
List<AskodoxBleProfile> askodoxProfilesFor(Iterable<String> serviceUuids) {
  final shorts = {for (final u in serviceUuids) askodoxShortUuid(u)}..remove(null);
  return [for (final p in askodoxBleProfiles) if (shorts.contains(p.service)) p];
}

class AskodoxReading {
  const AskodoxReading(this.kind, this.value, this.unit, {this.note});
  final String kind;
  final double value;
  final String unit;
  final String? note;

  String formatted() {
    final digits = unit == '%' || unit == 'bpm' ? 0 : (unit == 'kg' || unit == 'lb' ? 2 : 1);
    return '${value.toStringAsFixed(digits)} $unit';
  }
}

int _u16(List<int> b, int i) => b[i] | (b[i + 1] << 8);
int _s16(List<int> b, int i) {
  final v = _u16(b, i);
  return v >= 0x8000 ? v - 0x10000 : v;
}

/// Weight Measurement 0x2A9D: flags bit0 = imperial (lb, 0.01) else SI (kg, 0.005).
/// The special value 0xFFFF means "measurement unsuccessful".
AskodoxReading? askodoxDecodeWeight(List<int> b) {
  if (b.length < 3) return null;
  final imperial = b[0] & 0x01 == 1;
  final raw = _u16(b, 1);
  if (raw == 0xFFFF) return null;
  return imperial ? AskodoxReading('weight', raw * 0.01, 'lb') : AskodoxReading('weight', raw * 0.005, 'kg');
}

/// Environmental Sensing Temperature 0x2A6E: sint16, 0.01 °C (0x8000 = unknown).
AskodoxReading? askodoxDecodeEnvTemperature(List<int> b) {
  if (b.length < 2) return null;
  final raw = _s16(b, 0);
  if (raw == -0x8000) return null;
  return AskodoxReading('temperature', raw / 100, '°C');
}

/// Environmental Sensing Humidity 0x2A6F: uint16, 0.01 % (0xFFFF = unknown).
AskodoxReading? askodoxDecodeHumidity(List<int> b) {
  if (b.length < 2) return null;
  final raw = _u16(b, 0);
  if (raw == 0xFFFF || raw > 10000) return null;
  return AskodoxReading('humidity', raw / 100, '%');
}

/// IEEE-11073 32-bit FLOAT: 8-bit signed exponent (high byte), 24-bit signed mantissa.
double? askodoxIeee11073Float(List<int> b, int i) {
  if (b.length < i + 4) return null;
  var mantissa = b[i] | (b[i + 1] << 8) | (b[i + 2] << 16);
  if (mantissa >= 0x800000) mantissa -= 0x1000000;
  var exponent = b[i + 3];
  if (exponent >= 0x80) exponent -= 0x100;
  // Reserved special values: NaN, NRes, +INFINITY, -INFINITY, reserved.
  if (const {0x7FFFFF, -0x800000, 0x7FFFFE, -0x7FFFFE, -0x7FFFFF}.contains(mantissa)) return null;
  var value = mantissa.toDouble();
  if (exponent > 0) {
    for (var k = 0; k < exponent; k++) {
      value *= 10;
    }
  } else {
    for (var k = 0; k < -exponent; k++) {
      value /= 10;
    }
  }
  return value;
}

/// Health Thermometer Temperature Measurement 0x2A1C: flags bit0 = Fahrenheit.
AskodoxReading? askodoxDecodeThermometer(List<int> b) {
  if (b.length < 5) return null;
  final value = askodoxIeee11073Float(b, 1);
  if (value == null) return null;
  return AskodoxReading('temperature', value, b[0] & 0x01 == 1 ? '°F' : '°C');
}

/// Heart Rate Measurement 0x2A37: flags bit0 = uint16 value else uint8.
AskodoxReading? askodoxDecodeHeartRate(List<int> b) {
  if (b.length < 2) return null;
  final wide = b[0] & 0x01 == 1;
  if (wide && b.length < 3) return null;
  return AskodoxReading('heart_rate', (wide ? _u16(b, 1) : b[1]).toDouble(), 'bpm');
}

/// Battery Level 0x2A19: uint8 percent (0-100).
AskodoxReading? askodoxDecodeBattery(List<int> b) {
  if (b.isEmpty || b[0] > 100) return null;
  return AskodoxReading('battery', b[0].toDouble(), '%');
}

AskodoxReading? askodoxDecode(String characteristicUuid, List<int> bytes) => switch (askodoxShortUuid(characteristicUuid)) {
      '2a9d' => askodoxDecodeWeight(bytes),
      '2a6e' => askodoxDecodeEnvTemperature(bytes),
      '2a6f' => askodoxDecodeHumidity(bytes),
      '2a1c' => askodoxDecodeThermometer(bytes),
      '2a37' => askodoxDecodeHeartRate(bytes),
      '2a19' => askodoxDecodeBattery(bytes),
      _ => null,
    };

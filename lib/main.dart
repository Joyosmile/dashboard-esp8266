import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

void main() => runApp(const SupraEcuApp());

class SupraEcuApp extends StatelessWidget {
  const SupraEcuApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1F1F1F)),
      ),
      home: const MainNavigationPage(),
    );
  }
}

// ================= NAVIGATION PAGE (ROOT) =================
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;
  final WebSocketChannel _channel = WebSocketChannel.connect(Uri.parse('ws://192.168.4.1:81'));
  late Stream<dynamic> _broadcastStream;

  @override
  void initState() {
    super.initState();
    _broadcastStream = _channel.stream.asBroadcastStream();
  }

  @override
  void dispose() {
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      DashboardPage(stream: _broadcastStream),
      RawDataTablePage(stream: _broadcastStream),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1F1F1F),
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_on), label: 'Raw Table (30 Hex)'),
        ],
      ),
    );
  }
}

// ================= HALAMAN 1: DASHBOARD MONITOR =================
class DashboardPage extends StatefulWidget {
  final Stream<dynamic> stream;
  const DashboardPage({super.key, required this.stream});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int rpm = 0;
  double tps = 0.0, ect = 0.0, injector = 0.0, battery = 0.0, o2Voltage = 0.0, afrAktual = 14.7;
  String ecuIdText = "Membaca ECU ID..."; // Menampung data ID ECU dari ESP8266
  
  final List<EcuSnapshot> _ecuHistory = [];
  final int _maxDataPoints = 30;
  int timeCounter = 0;
  String selectedGraph = 'RPM';

  double _convertToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  Color _getAfrColor(double afr) {
    if (afr < 13.5) return Colors.cyan;
    if (afr > 15.2) return Colors.red;
    return Colors.green;
  }

  double _getGridInterval() {
    if (selectedGraph == 'TPS') return 20;
    if (selectedGraph == 'AFR') return 2;
    return 2000;
  }

  @override
  void initState() {
    super.initState();
    widget.stream.listen((message) {
      if (!mounted) return;
      try {
        final Map<String, dynamic> data = jsonDecode(message.toString());
        setState(() {
          rpm = data['rpm'] ?? 0;
          tps = _convertToDouble(data['tps']);
          ect = _convertToDouble(data['ect']);
          injector = _convertToDouble(data['inj']);
          battery = _convertToDouble(data['bat']);
          
          // Menerima data ID ECU String langsung dari ESP8266
          ecuIdText = data['ecu_id'] ?? "Tidak Diketahui";

          o2Voltage = ((data['o2'] ?? 0) * 0.0049 * 1000).round() / 1000;
          double afrFb = _convertToDouble(data['afr_fb'] == 0 ? 128 : data['afr_fb']);
          afrAktual = ((afrFb / 128.0) * 14.7 * 100).round() / 100;

          timeCounter++;
          _ecuHistory.add(EcuSnapshot(
            time: timeCounter.toDouble(),
            rpm: rpm.toDouble(),
            tps: tps,
            afr: afrAktual,
          ));

          if (_ecuHistory.length > _maxDataPoints) {
            _ecuHistory.removeAt(0);
          }
        });
      } catch (e) {
        // Abaikan jika format tidak cocok
      }
    });
  }

  List<FlSpot> _getSelectedSpots() {
    return _ecuHistory.map((snapshot) {
      double yValue = snapshot.rpm;
      if (selectedGraph == 'TPS') yValue = snapshot.tps;
      if (selectedGraph == 'AFR') yValue = snapshot.afr;
      return FlSpot(snapshot.time, yValue);
    }).toList();
  }

  double _getMinX() => _ecuHistory.isEmpty ? 0 : _ecuHistory.first.time;
  double _getMaxX() => _ecuHistory.isEmpty ? 30 : _ecuHistory.last.time;

  Widget _buildGraphButton(String label, Color color) {
    bool isSelected = selectedGraph == label;
    return InkWell(
      onTap: () => setState(() => selectedGraph = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey),
        ),
      ),
    );
  }

  Widget _buildRpmGauge() {
    return Container(
      height: 180,
      decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12)),
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: 0,
            maximum: 12000,
            showLabels: false,
            showTicks: false,
            startAngle: 180,
            endAngle: 0,
            radiusFactor: 0.9,
            canScaleToFit: true,
            axisLineStyle: const AxisLineStyle(
              thickness: 0.1,
              color: Color(0xFF2D2D2D),
              thicknessUnit: GaugeSizeUnit.factor,
            ),
            pointers: <GaugePointer>[
              RangePointer(
                value: rpm.toDouble(),
                width: 0.1,
                pointerOffset: 0,
                sizeUnit: GaugeSizeUnit.factor,
                gradient: const SweepGradient(
                  colors: <Color>[Colors.green, Colors.yellow, Colors.red],
                  stops: <double>[0.0, 0.6, 0.85],
                ),
              ),
              NeedlePointer(
                value: rpm.toDouble(),
                needleLength: 0.7,
                needleColor: Colors.red,
                needleStartWidth: 1,
                needleEndWidth: 4,
                knobStyle: const KnobStyle(knobRadius: 0.06, color: Colors.grey),
              )
            ],
            annotations: <GaugeAnnotation>[
              GaugeAnnotation(
                angle: 90,
                positionFactor: 0.4,
                widget: Column(
                  children: [
                    Text('$rpm', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Text('RPM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDataCard(String title, String value, Color accentColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HONDA SUPRA X 125 - ECU MONITOR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 14)),
        centerTitle: true,
        actions: [
          Icon(Icons.wifi, color: _ecuHistory.isEmpty ? Colors.red : Colors.green), 
          const SizedBox(width: 15)
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              
              // ================= TAMPILAN ID ECU DI ATAS METER RPM =================
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.developer_board, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "CONNECTED ECU ID :",
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                  Text(
                    ecuIdText,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            // ==============================================================================
            _buildRpmGauge(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildDataCard("BUKAAN GAS (TPS)", "$tps %", Colors.green, Icons.speed)),
                const SizedBox(width: 10),
                Expanded(child: _buildDataCard("SUHU OLI (EOT/ECT)", "$ect °C", Colors.orange, Icons.thermostat)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildDataCard("DURASI INJEKTOR", "$injector ms", Colors.cyan, Icons.shutter_speed)),
                const SizedBox(width: 10),
                Expanded(child: _buildDataCard("ACCU / BATERAI", "$battery V", Colors.yellow, Icons.battery_charging_full)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildDataCard("VOLTASE SENSOR O2", "$o2Voltage V", Colors.purpleAccent, Icons.waves)),
                const SizedBox(width: 10),
                Expanded(child: _buildDataCard("AFR FEEDBACK", "$afrAktual", _getAfrColor(afrAktual), Icons.analytics)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("GRAFIK HISTORI DATA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                Container(
                  decoration: BoxDecoration(color: const Color(0xFF2D2D2D), borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _buildGraphButton('RPM', Colors.red),
                      const SizedBox(width: 4),
                      _buildGraphButton('TPS', Colors.green),
                      const SizedBox(width: 4),
                      _buildGraphButton('AFR', Colors.blueAccent),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              padding: const EdgeInsets.only(top: 16, bottom: 12, right: 16, left: 4),
              decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12)),
              child: LineChart(
                LineChartData(
                  clipData: const FlClipData.all(),
                  minX: _getMinX(),
                  maxX: _getMaxX(),
                  minY: selectedGraph == 'AFR' ? 10 : 0,
                  maxY: selectedGraph == 'RPM' ? 12000 : (selectedGraph == 'TPS' ? 100 : 20),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _getGridInterval(),
                    getDrawingHorizontalLine: (value) => const FlLine(color: Colors.grey, strokeWidth: 0.5),
                  ),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _getSelectedSpots(),
                      isCurved: true,
                      barWidth: 2,
                      color: selectedGraph == 'RPM' ? Colors.red : (selectedGraph == 'TPS' ? Colors.green : Colors.blueAccent),
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= HALAMAN 2: ORIGINAL RAW DATA PAGE =================
class RawDataTablePage extends StatefulWidget {
  final Stream<dynamic> stream;
  const RawDataTablePage({super.key, required this.stream});

  @override
  State<RawDataTablePage> createState() => _RawDataTablePageState();
}

class _RawDataTablePageState extends State<RawDataTablePage> {
  List<dynamic> rawBytes = [];

  @override
  void initState() {
    super.initState();
    widget.stream.listen((message) {
      if (!mounted) return;
      try {
        final Map<String, dynamic> data = jsonDecode(message.toString());
        if (data.containsKey('raw')) {
          setState(() {
            rawBytes = data['raw'];
          });
        }
      } catch (e) {
        // Abaikan
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RAW DATA OBD TABLE (30)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("DATA LIVE STREAM BUFFER ECU :", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
            const SizedBox(height: 15),
            Expanded(
              child: rawBytes.isEmpty
                  ? const Center(child: Text("Menunggu data stream..."))
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.2,
                      ),
                      itemCount: rawBytes.length,
                      itemBuilder: (context, index) {
                        int val = int.tryParse(rawBytes[index].toString()) ?? 0;
                        String hexString = val.toRadixString(16).toUpperCase().padLeft(2, '0');
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F1F1F),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("[$index]", style: const TextStyle(fontSize: 9, color: Colors.grey)),
                              Text("0x$hexString", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Model snapshot data pendukung grafik histori dashboard
class EcuSnapshot {
  final double time;
  final double rpm;
  final double tps;
  final double afr;
  EcuSnapshot({required this.time, required this.rpm, required this.tps, required this.afr});
}

                          

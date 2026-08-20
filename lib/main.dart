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
                      getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFF333333), strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 45,
                          interval: _getGridInterval(),
                          getTitlesWidget: (value, meta) {
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              space: 8,
                              child: Text(
                                selectedGraph == 'AFR' ? value.toStringAsFixed(1) : value.toInt().toString(),
                                style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _getSelectedSpots(),
                        isCurved: true,
                        color: _getSelectedGraphColor(),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: _getSelectedGraphColor().withOpacity(0.12)),
                      ),
                    ],
                  ),
                  duration: Duration.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRpmGauge() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          const Text("ENGINE REVOLUTION (RPM)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: SfRadialGauge(
              axes: <RadialAxis>[
                RadialAxis(
                  minimum: 0,
                  maximum: 12000,
                  interval: 2000,
                  showLabels: true,
                  showTicks: true,
                  axisLabelStyle: const GaugeTextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                  majorTickStyle: const MajorTickStyle(length: 10, thickness: 2, color: Colors.white),
                  minorTickStyle: const MinorTickStyle(length: 5, thickness: 1, color: Colors.grey),
                  axisLineStyle: const AxisLineStyle(thickness: 12, color: Color(0xFF2D2D2D)),
                  pointers: <GaugePointer>[
                    NeedlePointer(
                      value: rpm.toDouble(),
                      needleColor: Colors.red,
                      knobStyle: const KnobStyle(color: Colors.red, sizeUnit: GaugeSizeUnit.factor, knobRadius: 0.08),
                    )
                  ],
                  annotations: <GaugeAnnotation>[
                    GaugeAnnotation(
                      angle: 90,
                      positionFactor: 0.5,
                      widget: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$rpm', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                          const Text('RPM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                        ],
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildGraphButton(String label, Color color) {
    bool isSelected = selectedGraph == label;
    return GestureDetector(
      onTap: () => setState(() => selectedGraph = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: isSelected ? color : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.black : Colors.grey)),
      ),
    );
  }

  double _getGridInterval() => selectedGraph == 'RPM' ? 3000 : (selectedGraph == 'TPS' ? 25 : 2);
  Color _getSelectedGraphColor() => selectedGraph == 'RPM' ? Colors.red : (selectedGraph == 'TPS' ? Colors.green : Colors.blueAccent);
  Color _getAfrColor(double val) => val < 13.5 ? Colors.blue : (val <= 14.8 ? Colors.green : Colors.redAccent);
}

// ================= HALAMAN 2: TABEL DATA MENTAH 30 HEXADECIMAL =================
class RawDataTablePage extends StatefulWidget {
  final Stream<dynamic> stream;
  const RawDataTablePage({super.key, required this.stream});

  @override
  State<RawDataTablePage> createState() => _RawDataTablePageState();
}

class _RawDataTablePageState extends State<RawDataTablePage> {
  List<String> _hexList = List.generate(30, (_) => "00");
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    widget.stream.listen((message) {
      if (!mounted || _isPaused) return;
      try {
        final Map<String, dynamic> parsedJson = jsonDecode(message.toString());
        if (parsedJson.containsKey('raw_hex') && parsedJson['raw_hex'] is List) {
          List<dynamic> jsonList = parsedJson['raw_hex'];
          setState(() {
            for (int i = 0; i < 30; i++) {
              if (i < jsonList.length) {
                _hexList[i] = jsonList[i].toString().toUpperCase().padLeft(2, '0');
              } else {
                _hexList[i] = "00";
              }
            }
          });
        }
      } catch (e) {
        // Abaikan error pemformatan string
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ECU SCANNER - 30 HEX DATA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: _isPaused ? Colors.green : Colors.yellow),
            onPressed: () => setState(() => _isPaused = !_isPaused),
          ),
          const SizedBox(width: 10)
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              // PERBAIKAN: Mengubah EdgeInsets.bottom menjadi EdgeInsets.only
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _isPaused ? Colors.orange.withOpacity(0.15) : Colors.cyan.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(_isPaused ? Icons.pause_circle : Icons.sync, color: _isPaused ? Colors.orange : Colors.cyan, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isPaused ? "MONITOR DI-PAUSE (BEKU)" : "MENERIMA DATA ARRAY HEX SCANNER REALTIME",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _isPaused ? Colors.orange : Colors.cyan),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF2D2D2D),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Text("NAMA DATA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text("HEXADECIMAL VALUE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.cyanAccent)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                ),
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: 30,
                  itemBuilder: (context, index) {
                    final isEven = index % 2 == 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      decoration: BoxDecoration(
                        color: isEven ? const Color(0xFF1F1F1F) : const Color(0xFF252525),
                        border: const Border(bottom: BorderSide(color: Color(0xFF2D2D2D), width: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Text(
                              "Data ${index + 1}",
                              style: const TextStyle(fontFamily: 'Courier', fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              "0x${_hexList[index]}",
                              style: const TextStyle(fontFamily: 'Courier', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EcuSnapshot {
  final double time;
  final double rpm;
  final double tps;
  final double afr;
EcuSnapshot({required this.time, required this.rpm, required this.tps, required this.afr});
}

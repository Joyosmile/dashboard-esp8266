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
  String ecuIdText = "Membaca ECU ID..."; 
  
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
        // Abaikan kegagalan parsing
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
      height: 200, 
      decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12)),
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: 0,
            maximum: 12000,
            showLabels: true, 
            showTicks: true,  
            interval: 2000,   
            labelOffset: 15,  
            axisLabelStyle: const GaugeTextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
            majorTickStyle: const MajorTickStyle(length: 8, thickness: 1.5, color: Colors.grey),
            minorTickStyle: const MinorTickStyle(length: 4, thickness: 1, color: Color(0xFF444444)),
            minorTicksPerInterval: 4,
            startAngle: 180,
            endAngle: 0,
            radiusFactor: 0.85, 
            canScaleToFit: true,
            axisLineStyle: const AxisLineStyle(
              thickness: 0.08,
              color: Color(0xFF2D2D2D),
              thicknessUnit: GaugeSizeUnit.factor,
            ),
            pointers: <GaugePointer>[
              RangePointer(
                value: rpm.toDouble(),
                width: 0.08,
                pointerOffset: 0,
                sizeUnit: GaugeSizeUnit.factor,
                gradient: const SweepGradient(
                  colors: <Color>[Colors.green, Colors.yellow, Colors.red],
                  stops: <double>[0.0, 0.6, 0.85],
                ),
              ),
              NeedlePointer(
                value: rpm.toDouble(),
                needleLength: 0.75,
                needleColor: Colors.red,
                needleStartWidth: 1,
                needleEndWidth: 4,
                knobStyle: const KnobStyle(knobRadius: 0.06, color: Colors.grey),
              )
            ],
            annotations: <GaugeAnnotation>[
              GaugeAnnotation(
                angle: 90,
                positionFactor: 0.45,
                widget: Column(
                  mainAxisSize: MainAxisSize.min,
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SUPRA FI ECU MONITOR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(ecuIdText, style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w500)),
          ],
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _buildRpmGauge(),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.5,
              children: [
                _buildDataCard('BUKAAN TPS', '$tps %', Colors.orange, Icons.speed),
                _buildDataCard('SUHU MESIN (ECT)', '$ect °C', Colors.blue, Icons.thermostat),
                _buildDataCard('INJEKTOR DURASI', '$injector ms', Colors.purple, Icons.shutter_speed),
                _buildDataCard('TEGANGAN AKI', '$battery V', Colors.green, Icons.battery_charging_full),
                _buildDataCard('TEGANGAN O2', '$o2Voltage V', Colors.indigo, Icons.electric_bolt),
                _buildDataCard('AIR FUEL RATIO (AFR)', '$afrAktual', _getAfrColor(afrAktual), Icons.air),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GRAFIK LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Row(
                        children: [
                          _buildGraphButton('RPM', Colors.red),
                          const SizedBox(width: 4),
                          _buildGraphButton('TPS', Colors.orange),
                          const SizedBox(width: 4),
                          _buildGraphButton('AFR', Colors.green),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 160, 
                    child: _ecuHistory.isEmpty
                        ? const Center(child: Text('Menunggu data masuk...', style: TextStyle(color: Colors.grey, fontSize: 12)))
                        : LineChart(
                            LineChartData(
                              minY: 0,
                              maxY: selectedGraph == 'RPM' ? 12000 : (selectedGraph == 'TPS' ? 100 : 20),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: true,
                                drawHorizontalLine: true,
                                horizontalInterval: _getGridInterval(),
                                getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFF2D2D2D), strokeWidth: 1),
                                getDrawingVerticalLine: (value) => FlLine(color: const Color(0xFF222222), strokeWidth: 1),
                              ),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 22,
                                    interval: 5, 
                                    getTitlesWidget: (value, meta) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          value.toStringAsFixed(0),
                                          style: const TextStyle(color: Colors.grey, fontSize: 8),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: selectedGraph == 'RPM' ? 42 : 30,
                                    interval: _getGridInterval(),
                                    getTitlesWidget: (value, meta) {
                                      if (value == meta.max) return const SizedBox.shrink();
                                      String text = selectedGraph == 'AFR' 
                                          ? value.toStringAsFixed(1) 
                                          : value.toStringAsFixed(0);
                                      return Text(
                                        text,
                                        style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.right,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              borderData: FlBorderData(
                                show: true,
                                border: const Border(
                                  left: BorderSide(color: Color(0xFF2D2D2D), width: 1),
                                  bottom: BorderSide(color: Color(0xFF2D2D2D), width: 1),
                                ),
                              ),
                              minX: _getMinX(),
                              maxX: _getMaxX(),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _getSelectedSpots(),
                                  isCurved: true,
                                  color: selectedGraph == 'RPM'
                                      ? Colors.red
                                      : (selectedGraph == 'TPS' ? Colors.orange : Colors.green),
                                  barWidth: 2,
                                  isStrokeCapRound: true,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(show: false),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
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

// ================= HALAMAN 2: RAW DATA TABLE (30 HEX) =================
class RawDataTablePage extends StatefulWidget {
  final Stream<dynamic> stream;
  const RawDataTablePage({super.key, required this.stream});

  @override
  State<RawDataTablePage> createState() => _RawDataTablePageState();
}

class _RawDataTablePageState extends State<RawDataTablePage> {
  List<int> rawBytes = List.filled(30, 0);
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    widget.stream.listen((message) {
      if (!mounted) return;
      try {
        final Map<String, dynamic> data = jsonDecode(message.toString());
        if (data.containsKey('raw_hex')) {
          final List<dynamic> parsedRaw = data['raw_hex'];
          setState(() {
            rawBytes = parsedRaw.map((e) => int.tryParse(e.toString()) ?? 0).toList();
          });
        }
      } catch (e) {
        // Abaikan kegagalan parsing
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = List.generate(rawBytes.length, (index) {
      final value = rawBytes[index];
      final hexStr = '0x${value.toRadixString(16).toUpperCase().padLeft(2, "0")}';
      return {
        'index': index,
        'indexHex': '0x${index.toRadixString(16).toUpperCase().padLeft(2, "0")}',
        'dec': value.toString(),
        'hex': hexStr,
      };
    });

    final filteredItems = items.where((item) {
      final query = _searchQuery.toLowerCase();
      return item['index'].toString().contains(query) ||
          item['indexHex'].toLowerCase().contains(query) ||
          item['dec'].contains(query) ||
          item['hex'].toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DATA STREAM BUFFER (30 HEX)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            key: const ValueKey('search_bar_container'),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Cari berdasarkan indeks atau nilai data (Hex/Dec)...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                filled: true,
                fillColor: const Color(0xFF1F1F1F),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: filteredItems.isEmpty
                ? const Center(child: Text('Data tidak ditemukan', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, idx) {
                      final item = filteredItems[idx];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F1F1F),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2D2D2D), width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 95,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1), 
                                borderRadius: BorderRadius.circular(4)
                              ),
                              child: Text(
                                '${item['indexHex']} (${item['index']})',
                                style: const TextStyle(color: Colors.redAccent, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 65,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('HEX', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
                                  Text(item['hex'], style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            SizedBox(
                              width: 50,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('DEC', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
                                  Text(item['dec'], style: const TextStyle(color: Colors.grey, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

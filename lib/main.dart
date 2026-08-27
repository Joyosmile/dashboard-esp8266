import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Kunci orientasi awal aplikasi ke Portrait
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SupraEcuApp());
}

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

// Model data untuk sinkronisasi state antar halaman secara real-time
class EcuState {
  int rpm = 0;
  double tps = 0.0;
  double ect = 0.0;
  double injector = 0.0;
  double battery = 0.0;
  double o2Voltage = 0.0;
  double afrAktual = 14.7;
  String ecuIdText = "Membaca ECU ID...";
  List<int> rawBytes = List.filled(30, 0);
  List<EcuSnapshot> history = [];
}

class EcuSnapshot {
  final double time;
  final double rpm;
  final double tps;
  final double afr;
  EcuSnapshot({required this.time, required this.rpm, required this.tps, required this.afr});
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
  
  final EcuState _state = EcuState();
  int _timeCounter = 0;
  final int _maxDataPoints = 30;

  @override
  void initState() {
    super.initState();
    _broadcastStream = _channel.stream.asBroadcastStream();
    
    // Sinkronisasi data masuk WebSocket secara terpusat di Root Widget
    _broadcastStream.listen((message) {
      if (!mounted) return;
      try {
        final Map<String, dynamic> data = jsonDecode(message.toString());
        setState(() {
          _state.rpm = data['rpm'] ?? 0;
          _state.tps = _convertToDouble(data['tps']);
          _state.ect = _convertToDouble(data['ect']);
          _state.injector = _convertToDouble(data['inj']);
          _state.battery = _convertToDouble(data['bat']);
          _state.ecuIdText = data['ecu_id'] ?? "Tidak Diketahui";

          _state.o2Voltage = ((data['o2'] ?? 0) * 0.0049 * 1000).round() / 1000;
          double afrFb = _convertToDouble(data['afr_fb'] == 0 ? 128 : data['afr_fb']);
          _state.afrAktual = ((afrFb / 128.0) * 14.7 * 100).round() / 100;

          if (data.containsKey('raw_hex')) {
            final List<dynamic> parsedRaw = data['raw_hex'];
            _state.rawBytes = parsedRaw.map((e) => int.tryParse(e.toString()) ?? 0).toList();
          }

          _timeCounter++;
          _state.history.add(EcuSnapshot(
            time: _timeCounter.toDouble(),
            rpm: _state.rpm.toDouble(),
            tps: _state.tps,
            afr: _state.afrAktual,
          ));

          if (_state.history.length > _maxDataPoints) {
            _state.history.removeAt(0);
          }
        });
      } catch (e) {
        // Gagal mengurai data JSON stream
      }
    });
  }

  double _convertToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  void dispose() {
    _channel.sink.close();
    super.dispose();
  }

  void _onItemTapped(int index) {
    // Kembalikan ke Portrait jika meninggalkan Halaman Grafik (index 1)
    if (_selectedIndex == 1 && index != 1) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      DashboardPage(state: _state),
      LiveGraphPage(state: _state),
      RawDataTablePage(state: _state),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1F1F1F),
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Grafik Live'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_on), label: 'Raw Table'),
        ],
      ),
    );
  }
}

// ================= HALAMAN 1: DASHBOARD MONITOR (PORTRAIT) =================
class DashboardPage extends StatelessWidget {
  final EcuState state;
  const DashboardPage({super.key, required this.state});

  Color _getAfrColor(double afr) {
    if (afr < 13.5) return Colors.cyan;
    if (afr > 15.2) return Colors.red;
    return Colors.green;
  }

  Widget _buildRpmGauge() {
    return Container(
      height: 160,
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
            radiusFactor: 0.95,
            centerX: 0.5,
            centerY: 0.75,
            canScaleToFit: true,
            axisLineStyle: const AxisLineStyle(
              thickness: 0.08,
              color: Color(0xFF2D2D2D),
              thicknessUnit: GaugeSizeUnit.factor,
            ),
            pointers: <GaugePointer>[
              RangePointer(
                value: state.rpm.toDouble(),
                width: 0.08,
                sizeUnit: GaugeSizeUnit.factor,
                gradient: const SweepGradient(
                  colors: <Color>[Colors.green, Colors.yellow, Colors.red],
                  stops: <double>[0.0, 0.6, 0.85],
                ),
              ),
              NeedlePointer(
                value: state.rpm.toDouble(),
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
                positionFactor: 0.2,
                widget: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${state.rpm}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
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
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
            Text(state.ecuIdText, style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w500)),
          ],
        ),
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
                _buildDataCard('BUKAAN TPS', '${state.tps} %', Colors.orange, Icons.speed),
                _buildDataCard('SUHU MESIN (ECT)', '${state.ect} °C', Colors.blue, Icons.thermostat),
                _buildDataCard('INJEKTOR DURASI', '${state.injector} ms', Colors.purple, Icons.shutter_speed),
                _buildDataCard('TEGANGAN AKI', '${state.battery} V', Colors.green, Icons.battery_charging_full),
                _buildDataCard('TEGANGAN O2', '${state.o2Voltage} V', Colors.indigo, Icons.electric_bolt),
                _buildDataCard('AIR FUEL RATIO (AFR)', '${state.afrAktual}', _getAfrColor(state.afrAktual), Icons.air),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================= HALAMAN 2: GRAFIK LIVE (LANDSCAPE OPTIMIZED) =================
class LiveGraphPage extends StatefulWidget {
  final EcuState state;
  const LiveGraphPage({super.key, required this.state});

  @override
  State<LiveGraphPage> createState() => _LiveGraphPageState();
}

class _LiveGraphPageState extends State<LiveGraphPage> {
  String selectedGraph = 'RPM';

  @override
  void initState() {
    super.initState();
    // Paksa rotasi layar ke kiri atau kanan saat halaman ini dibuka aktif
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  double _getGridInterval() {
    if (selectedGraph == 'TPS') return 20;
    if (selectedGraph == 'AFR') return 2;
    return 2000;
  }

  List<FlSpot> _getSelectedSpots() {
    return widget.state.history.map((snapshot) {
      double yValue = snapshot.rpm;
      if (selectedGraph == 'TPS') yValue = snapshot.tps;
      if (selectedGraph == 'AFR') yValue = snapshot.afr;
      return FlSpot(snapshot.time, yValue);
    }).toList();
  }

  double _getMinX() => widget.state.history.isEmpty ? 0 : widget.state.history.first.time;
  double _getMaxX() => widget.state.history.isEmpty ? 30 : widget.state.history.last.time;

  Widget _buildGraphButton(String label, Color color) {
    bool isSelected = selectedGraph == label;
    return InkWell(
      onTap: () => setState(() => selectedGraph = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? Colors.transparent : Colors.grey.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('LIVE TELEMETRY GRAPH', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                  Row(
                    children: [
                      _buildGraphButton('RPM', Colors.red),
                      const SizedBox(width: 8),
                      _buildGraphButton('TPS', Colors.orange),
                      const SizedBox(width: 8),
                      _buildGraphButton('AFR', Colors.green),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(right: 20, left: 10, top: 10),
                  decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12)),
                  child: widget.state.history.isEmpty
                      ? const Center(child: Text('Menunggu data masuk...', style: TextStyle(color: Colors.grey)))
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
                                    return Text(
                                      value.toStringAsFixed(0),
                                      style: const TextStyle(color: Colors.grey, fontSize: 9),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: selectedGraph == 'RPM' ? 45 : 35,
                                  interval: _getGridInterval(),
                                  getTitlesWidget: (value, meta) {
                                    if (value == meta.max) return const SizedBox.shrink();
                                    String text = selectedGraph == 'AFR' ? value.toStringAsFixed(1) : value.toStringAsFixed(0);
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
                                barWidth: 2.5,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= HALAMAN 3: RAW DATA TABLE (30 HEX) =================
class RawDataTablePage extends StatefulWidget {
  final EcuState state;
  const RawDataTablePage({super.key, required this.state});

  @override
  State<RawDataTablePage> createState() => _RawDataTablePageState();
}

class _RawDataTablePageState extends State<RawDataTablePage> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = List.generate(widget.state.rawBytes.length, (index) {
      final value = widget.state.rawBytes[index];
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
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
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
                              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
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

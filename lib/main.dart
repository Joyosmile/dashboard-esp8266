import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16161D),
          elevation: 0,
          centerTitle: false,
        ),
        cardColor: const Color(0xFF1A1A24),
      ),
      home: const MainNavigationPage(),
    );
  }
}

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
  final int _maxDataPoints = 40;

  @override
  void initState() {
    super.initState();
    _broadcastStream = _channel.stream.asBroadcastStream();
    
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
        // Handle error parse
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF232330), width: 1)),
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF16161D),
          selectedItemColor: Colors.redAccent,
          unselectedItemColor: Colors.grey.shade600,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.analytics_rounded), label: 'Grafik Live'),
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Raw Table'),
          ],
        ),
      ),
    );
  }
}

// ================= HALAMAN 1: DASHBOARD MONITOR (PORTRAIT) =================
class DashboardPage extends StatelessWidget {
  final EcuState state;
  const DashboardPage({super.key, required this.state});

  Color _getAfrColor(double afr) {
    if (afr < 12.5) return Colors.cyanAccent; // Sangat kaya (Rich)
    if (afr < 14.7) return Colors.greenAccent; // Kaya / Optimal bertenaga
    if (afr > 15.2) return Colors.orangeAccent; // Miskin (Lean)
    return Colors.green;
  }

  Widget _buildRpmGauge() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232330), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: 0,
            maximum: 12000,
            showLabels: true,
            showTicks: true,
            interval: 2000,
            labelOffset: 18,
            axisLabelStyle: const GaugeTextStyle(color: Color(0xFF8E8E9F), fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
            majorTickStyle: const MajorTickStyle(length: 10, thickness: 2, color: Color(0xFF444454)),
            minorTickStyle: const MinorTickStyle(length: 5, thickness: 1, color: Color(0xFF2D2D3A)),
            minorTicksPerInterval: 4,
            startAngle: 170,
            endAngle: 10,
            radiusFactor: 0.95,
            centerX: 0.5,
            centerY: 0.65,
            canScaleToFit: true,
            axisLineStyle: const AxisLineStyle(
              thickness: 0.06,
              color: Color(0xFF232330),
              thicknessUnit: GaugeSizeUnit.factor,
            ),
            pointers: <GaugePointer>[
              RangePointer(
                value: state.rpm.toDouble(),
                width: 0.06,
                sizeUnit: GaugeSizeUnit.factor,
                gradient: const SweepGradient(
                  colors: <Color>[Colors.greenAccent, Colors.yellowAccent, Colors.redAccent],
                  stops: <double>[0.0, 0.65, 0.85],
                ),
              ),
              NeedlePointer(
                value: state.rpm.toDouble(),
                needleLength: 0.8,
                needleColor: Colors.redAccent,
                needleStartWidth: 1,
                needleEndWidth: 5,
                knobStyle: const KnobStyle(
                  knobRadius: 0.07,
                  color: Color(0xFF232330),
                  borderColor: Colors.redAccent,
                  borderWidth: 1.5,
                ),
              )
            ],
            annotations: <GaugeAnnotation>[
              GaugeAnnotation(
                angle: 90,
                positionFactor: 0.4,
                widget: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${state.rpm}',
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, fontFamily: 'monospace', letterSpacing: -1),
                    ),
                    const Text(
                      'RPM',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent, letterSpacing: 1.5),
                    ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232330), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF8E8E9F), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
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
            const Text('SUPRA FI ECU TELEMETRY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  'ID: ${state.ecuIdText}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500, fontFamily: 'monospace'),
                ),
              ],
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildRpmGauge(),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.3,
              children: [
                _buildDataCard('TPS OPENING', '${state.tps}%', Colors.orangeAccent, Icons.speed_rounded),
                _buildDataCard('ENG TEMP (ECT)', '${state.ect}°C', Colors.blueAccent, Icons.thermostat_rounded),
                _buildDataCard('INJ DURATION', '${state.injector}ms', Colors.purpleAccent, Icons.timelapse_rounded),
                _buildDataCard('BATT VOLTAGE', '${state.battery}V', Colors.greenAccent, Icons.battery_charging_full_rounded),
                _buildDataCard('O2 SENSOR', '${state.o2Voltage}V', Colors.indigoAccent, Icons.bolt_rounded),
                _buildDataCard('AFR TARGET', '${state.afrAktual}', _getAfrColor(state.afrAktual), Icons.air_rounded),
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
  double _getMaxX() => widget.state.history.isEmpty ? 40 : widget.state.history.last.time;

  Widget _buildGraphButton(String label, Color color) {
    bool isSelected = selectedGraph == label;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: InkWell(
        onTap: () => setState(() => selectedGraph = label),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? color : const Color(0xFF232330), width: 1.5),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? color : const Color(0xFF8E8E9F), letterSpacing: 1),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color activeColor = Colors.redAccent;
    if (selectedGraph == 'TPS') activeColor = Colors.orangeAccent;
    if (selectedGraph == 'AFR') activeColor = Colors.greenAccent;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text('${selectedGraph} REAL-TIME GRAPH', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    ],
                  ),
                  Row(
                    children: [
                      _buildGraphButton('RPM', Colors.redAccent),
                      const SizedBox(width: 8),
                      _buildGraphButton('TPS', Colors.orangeAccent),
                      const SizedBox(width: 8),
                      _buildGraphButton('AFR', Colors.greenAccent),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(right: 24, left: 12, top: 16, bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161D), 
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF232330), width: 1),
                  ),
                  child: widget.state.history.isEmpty
                      ? const Center(child: Text('Menunggu transmisi data ECU...', style: TextStyle(color: Color(0xFF8E8E9F), fontSize: 13)))
                      : LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: selectedGraph == 'RPM' ? 12000 : (selectedGraph == 'TPS' ? 100 : 20),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: true,
                              drawHorizontalLine: true,
                              horizontalInterval: _getGridInterval(),
                              getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFF232330), strokeWidth: 1),
                              getDrawingVerticalLine: (value) => FlLine(color: const Color(0xFF1D1D26), strokeWidth: 1),
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 24,
                                  getTitlesWidget: (value, meta) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6.0),
                                      child: Text(
                                        value.toStringAsFixed(0),
                                        style: const TextStyle(color: Color(0xFF545464), fontSize: 10, fontFamily: 'monospace'),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: selectedGraph == 'RPM' ? 48 : 36,
                                  interval: _getGridInterval(),
                                  getTitlesWidget: (value, meta) {
                                    if (value == meta.max) return const SizedBox.shrink();
                                    String text = selectedGraph == 'AFR' ? value.toStringAsFixed(1) : value.toStringAsFixed(0);
                                    return Text(
                                      text,
                                      style: const TextStyle(color: Color(0xFF8E8E9F), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                      textAlign: TextAlign.right,
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            minX: _getMinX(),
                            maxX: _getMaxX(),
                            lineBarsData: [
                              LineChartBarData(
                                spots: _getSelectedSpots(),
                                isCurved: true,
                                curveSmoothness: 0.2,
                                color: activeColor,
                                barWidth: 3,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [activeColor.withOpacity(0.2), activeColor.withOpacity(0.0)],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
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
    final List<Map<String, dynamic>> secureItems = List.generate(widget.state.rawBytes.length, (index) {
      final value = widget.state.rawBytes[index];
      final hexStr = '0x${value.toRadixString(16).toUpperCase().padLeft(2, "0")}';
      return {
        'index': index,
        'indexHex': '0x${index.toRadixString(16).toUpperCase().padLeft(2, "0")}',
        'dec': value.toString(),
        'hex': hexStr,
      };
    });

    final filteredItems = secureItems.where((item) {
      final query = _searchQuery.toLowerCase();
      return item['index'].toString().contains(query) ||
          item['indexHex'].toLowerCase().contains(query) ||
          item['dec'].contains(query) ||
          item['hex'].toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DATA STREAM BUFFER (30 HEX)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Cari register index / nilai (Hex/Dec)...',
                hintStyle: const TextStyle(color: Color(0xFF545464), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF8E8E9F), size: 20),
                filled: true,
                fillColor: const Color(0xFF16161D),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), 
                  borderSide: const BorderSide(color: Color(0xFF232330), width: 1)
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), 
                  borderSide: const BorderSide(color: Color(0xFF232330), width: 1)
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), 
                  borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredItems.isEmpty
                ? const Center(child: Text('Data Stream tidak ditemukan', style: TextStyle(color: Color(0xFF8E8E9F))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, idx) {
                      final item = filteredItems[idx];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF232330), width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.08), 
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.2), width: 1)
                              ),
                              child: Text(
                                '${item['indexHex']} [${item['index']}]',
                                style: const TextStyle(color: Colors.redAccent, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('HEX', style: TextStyle(fontSize: 8, color: Color(0xFF545464), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                const SizedBox(height: 2),
                                Text(item['hex'], style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(width: 28),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('DEC', style: TextStyle(fontSize: 8, color: Color(0xFF545464), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                const SizedBox(height: 2),
                                Text(item['dec'], style: const TextStyle(color: Color(0xFF8E8E9F), fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
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

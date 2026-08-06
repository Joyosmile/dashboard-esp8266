import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

void main() {
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
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // IP Access Point bawaan ESP8266 port standar websocket 81
  final _channel = WebSocketChannel.connect(Uri.parse('ws://192.168.4.1:81'));

  // Variabel Data ECU Supra X 125
  int rpm = 0;
  double tps = 0.0;
  double ect = 0.0;
  double injector = 0.0;
  double battery = 0.0;

  // Variabel untuk Grafik Histori (Maksimal menyimpan 30 data terakhir)
  List<FlSpot> rpmSpots = [];
  List<FlSpot> tpsSpots = [];
  int timeCounter = 0;
  String selectedGraph = 'RPM'; // Opsi pilihan grafik: 'RPM' atau 'TPS'

  @override
  void initState() {
    super.initState();
    _channel.stream.listen((message) {
      try {
        final Map<String, dynamic> data = jsonDecode(message);
        setState(() {
          rpm = data['rpm'] ?? 0;
          tps = (data['tps'] ?? 0).toDouble();
          ect = (data['ect'] ?? 0).toDouble();
          injector = (data['inj'] ?? 0).toDouble();
          battery = (data['bat'] ?? 0).toDouble();

          timeCounter++;
          rpmSpots.add(FlSpot(timeCounter.toDouble(), rpm.toDouble()));
          tpsSpots.add(FlSpot(timeCounter.toDouble(), tps));

          if (rpmSpots.length > 30) {
            rpmSpots.removeAt(0);
            tpsSpots.removeAt(0);
          }
        });
      } catch (e) {
        debugPrint("Error parsing data: $e");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HONDA SUPRA X 125 - ECU MONITOR', 
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 14)),
        centerTitle: true,
        actions: [
          Icon(Icons.wifi, color: rpmSpots.isEmpty ? Colors.red : Colors.green),
          const SizedBox(width: 15),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // GRID 1: Indikator Utama RPM (Besar & Center)
              _buildRpmGauge(),
              const SizedBox(height: 12),

              // GRID 2: Parameter Digital Lainnya (TPS, ECT, INJ, BAT)
              Row(
                children: [
                  Expanded(child: _buildDataCard("BUKAAN GAS (TPS)", "$tps %", Colors.green, Icons.speed)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildDataCard("SUHU MESIN (ECT)", "$ect °C", Colors.orange, Icons.thermostat)),
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
              const SizedBox(height: 20),

              // JUDUL & TOMBOL SELEKSI BERSAMPINGAN (RPM & TPS)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("GRAFIK HISTORI DATA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                  // Desain Tombol Berdampingan Modern
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _buildGraphButton('RPM', Colors.red),
                        const SizedBox(width: 4),
                        _buildGraphButton('TPS', Colors.green),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // BOX GRAFIK HISTORI DENGAN SKALA YANG DIPERBAIKI
              Container(
                height: 200,
                padding: const EdgeInsets.only(top: 16, bottom: 12, right: 16, left: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: LineChart(
                  LineChartData(
                    // Mengaktifkan garis kisi (grid) latar belakang agar skala mudah dibaca
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) {
                        return const FlLine(color: Color(0xFF333333), strokeWidth: 1);
                      },
                    ),
                    // Pengaturan teks skala angka di sisi kiri dan bawah
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Sumbu X dilewati karena berupa realtime-waktu
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 45,
                          getTitlesWidget: (value, meta) {
                            // Menampilkan skala angka yang pas agar tidak bertumpuk
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(
                                value.toInt().toString(),
                                style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    // Menentukan batas atas dan bawah skala Y secara dinamis
                    minY: 0,
                    maxY: selectedGraph == 'RPM' ? 10000 : 100, // RPM max 10k, TPS max 100%
                    lineBarsData: [
                      LineChartBarData(
                        spots: selectedGraph == 'RPM' ? rpmSpots : tpsSpots,
                        isCurved: true,
                        color: selectedGraph == 'RPM' ? Colors.red : Colors.green,
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: (selectedGraph == 'RPM' ? Colors.red : Colors.green).withOpacity(0.12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Fungsi pembuat tombol seleksi grafis berdampingan
  Widget _buildGraphButton(String label, Color activeColor) {
    bool isSelected = selectedGraph == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedGraph = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // Widget Pembuat Gauge RPM Bundar
  Widget _buildRpmGauge() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: 0,
            maximum: 12000,
            pointers: <GaugePointer>[
              NeedlePointer(value: rpm.toDouble(), needleColor: Colors.red, knobStyle: const KnobStyle(color: Colors.white)),
            ],
            ranges: <GaugeRange>[
              GaugeRange(startValue: 0, endValue: 7000, color: Colors.green),
              GaugeRange(startValue: 7000, endValue: 9500, color: Colors.orange),
              GaugeRange(startValue: 9500, endValue: 12000, color: Colors.red),
            ],
            annotations: <GaugeAnnotation>[
              GaugeAnnotation(
                widget: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
Text('$rpm', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
const Text('RPM', style: TextStyle(fontSize: 12, color: Colors.grey)),
],
),
angle: 90, positionFactor: 0.5,
)
],
)
],
),
);
}
// Widget Pembuat Kartu Informasi Digital
Widget _buildDataCard(String title, String value, Color color, IconData icon) {
return Container(
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: const Color(0xFF1F1F1F),
borderRadius: BorderRadius.circular(12),
),
child: Column(
cross bales: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(icon, color: color, size: 16),
const SizedBox(width: 6),
Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
],
),
const SizedBox(height: 8),
Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
],
),
);
}
@override
void dispose() {
_channel.sink.close();
super.dispose();
}
}

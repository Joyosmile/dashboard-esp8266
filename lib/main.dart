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
State createState() => _DashboardPageState();
} 

class _DashboardPageState extends State {
final _channel = WebSocketChannel.connect(Uri.parse('ws://192.168.4.1:81')); 

int rpm = 0;
double tps = 0.0;
double ect = 0.0; // Pada Supra X 125 Helm In (KYZ) ini mendeteksi EOT (Suhu Oli)
double injector = 0.0;
double battery = 0.0; 

// Parameter baru untuk parsing Table 20
double o2Voltage = 0.0;
double afrAktual = 14.7; 

List rpmSpots = [];
List tpsSpots = [];
List afrSpots = []; // Riwayat grafik baru untuk AFR
int timeCounter = 0;
String selectedGraph = 'RPM'; 

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

  // Parsing O2 Sensor (0V - 1V) dari data mentah desimal
  int rawO2 = data['o2'] ?? 0;
  o2Voltage = double.parse((rawO2 * 0.0049).toStringAsFixed(3));

  // Parsing AFR Feedback Coefficient (Desimal / 128 * 14.7)
  int rawAfrFb = data['afr_fb'] ?? 128; // Default 128 jika Lambda netral (1.0)
  afrAktual = double.parse(((rawAfrFb / 128) * 14.7).toStringAsFixed(2));

  timeCounter++;
  rpmSpots.add(FlSpot(timeCounter.toDouble(), rpm.toDouble()));
  tpsSpots.add(FlSpot(timeCounter.toDouble(), tps));
  afrSpots.add(FlSpot(timeCounter.toDouble(), afrAktual));

  if (rpmSpots.length > 30) {
    rpmSpots.removeAt(0);
    tpsSpots.removeAt(0);
    afrSpots.removeAt(0);
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
_buildRpmGauge(),
const SizedBox(height: 12), 

      Row(
        children: [
          Expanded(child: _buildDataCard("BUKAAN GAS (TPS)", "\$tps %", Colors.green, Icons.speed)),
          const SizedBox(width: 10),
          Expanded(child: _buildDataCard("SUHU OLI (EOT/ECT)", "\$ect °C", Colors.orange, Icons.thermostat)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _buildDataCard("DURASI INJEKTOR", "\$injector ms", Colors.cyan, Icons.shutter_speed)),
          const SizedBox(width: 10),
          Expanded(child: _buildDataCard("ACCU / BATERAI", "\$battery V", Colors.yellow, Icons.battery_charging_full)),
        ],
      ),
      const SizedBox(height: 10),
      
      // Tambahan baris kartu data O2 Sensor & AFR
      Row(
        children: [
          Expanded(child: _buildDataCard("VOLTASE SENSOR O2", "\$o2Voltage V", Colors.purpleAccent, Icons.waves)),
          const SizedBox(width: 10),
          Expanded(
            child: _buildDataCard(
              "AFR FEEDBACK", 
              "\$afrAktual", 
              _getAfrColor(afrAktual), 
              Icons.analytics
            )
          ),
        ],
      ),
      const SizedBox(height: 20),

      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("GRAFIK HISTORI DATA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
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
                const SizedBox(width: 4),
                _buildGraphButton('AFR', Colors.blueAccent),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),

      // BOX GRAFIK HISTORI
      Container(
        height: 200,
        padding: const EdgeInsets.only(top: 16, bottom: 12, right: 16, left: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(12),
        ),
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
              getDrawingHorizontalLine: (value) {
                return const FlLine(color: Color(0xFF333333), strokeWidth: 1);
              },
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
                        style: const TextStyle(
                          color: Colors.grey, 
                          fontSize: 10, 
                          fontWeight: FontWeight.bold,
                        ),
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
                belowBarData: BarAreaData(
                  show: true,
                  color: _getSelectedGraphColor().withOpacity(0.12),
                ),
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

// Fungsi pembantu untuk pewarnaan dinamis angka AFR
Color _getAfrColor(double value) {
if (value < 13.5) return Colors.blue; // Rich / Boros (Kelebihan bensin)
if (value >= 13.5 && value <= 14.8) return Colors.green; // Stoichiometric (Campuran Ideal)
return Colors.redAccent; // Lean / Kering (Kekurangan bensin)
} 

double _getMinX() {
if (selectedGraph == 'RPM') return rpmSpots.isNotEmpty ? rpmSpots.first.x : 0;
if (selectedGraph == 'TPS') return tpsSpots.isNotEmpty ? tpsSpots.first.x : 0;
return afrSpots.isNotEmpty ? afrSpots.first.x : 0;
} 

double _getMaxX() {
if (selectedGraph == 'RPM') return rpmSpots.isNotEmpty ? rpmSpots.last.x : 30;
if (selectedGraph == 'TPS') return tpsSpots.isNotEmpty ? tpsSpots.last.x : 30;
return afrSpots.isNotEmpty ? afrSpots.last.x : 30;
}
double _getGridInterval() {
if (selectedGraph == 'RPM') return 3000;
if (selectedGraph == 'TPS') return 25;
return 2.0; // Interval sumbu Y untuk grafik AFR (10, 12, 14, 16, dll)
}
List _getSelectedSpots() {
if (selectedGraph == 'RPM') return rpmSpots;
if (selectedGraph == 'TPS') return tpsSpots;
return afrSpots;
}
Color _getSelectedGraphColor() {
if (selectedGraph == 'RPM') return Colors.red;
if (selectedGraph == 'TPS') return Colors.green;
return Colors.blueAccent;
}
Widget _buildGraphButton(String label, Color color) {
bool isSelected = selectedGraph == label;
return GestureDetector(
onTap: () {
setState(() {
selectedGraph = label;
}
);
},
child: Container(
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
decoration: BoxDecoration(color: isSelected ? color : Colors.transparent,borderRadius: BorderRadius.circular(6),
),
child: Text(
label,
style: TextStyle(
fontSize: 11,
fontWeight: FontWeight.bold,
color: isSelected ? Colors.black : Colors.grey,
),
),
),
);
}
Widget _buildDataCard(
String title, String value, Color color, IconData icon) {
return Container(
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: const Color(0xFF1F1F1F),
borderRadius: BorderRadius.circular(12),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(
icon, color: color, size: 16),
const SizedBox(width: 6),
Text(
title, style: const TextStyle(
color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
],
),
const SizedBox(
height: 8),
Text(
value, style: const TextStyle(
fontSize: 18, fontWeight: FontWeight.bold)),
],
),
);
}
Widget _buildRpmGauge() {
return Container(
height: 180,
decoration: BoxDecoration(
color: const Color(0xFF1F1F1F),
borderRadius: BorderRadius.circular(12),
),
child: SfRadialGauge(
axes: [
RadialAxis(
minimum: 0,
maximum: 12000,
showLabels: false,
showTicks: false,
startAngle: 180,
endAngle: 0,
radiusFactor: 0.8,
canScaleToFit: true,
axisLineStyle: const AxisLineStyle(
thickness: 0.1,
color: Color(0xFF2D2D2D),
thicknessUnit: GaugeSizeUnit.factor,),
pointers: [
RangePointer(
value: rpm.toDouble(),
width: 0.1,
sizeUnit: GaugeSizeUnit.factor,
color: Colors.red,
enableAnimation: true,
animationDuration: 100,),
NeedlePointer(value: rpm.toDouble(),
needleLength: 0.7,
needleColor: Colors.white,
needleStartWidth: 1,
needleEndWidth: 4,
knobStyle: const KnobStyle(
knobRadius: 0.08, color: Colors.white),enableAnimation: true,
animationDuration: 100,
)
],
annotations: [
GaugeAnnotation(
widget: Column(
mainAxisSize: MainAxisSize.min,
children: [
Text(
rpm.toString(),
style: const TextStyle(
fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
),
const Text(
'RPM',
style: TextStyle(
fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
),
],
),
angle: 90,positionFactor: 0.6,)
],
)
],
),
);
}
}

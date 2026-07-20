import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'db/database_helper.dart';
import 'main.dart'; // For TrackingProvider

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  int? _tappedBarIndex;

  // Data from SQLite
  int _totalTraffic = 0;
  double _avgDwellMinutes = 0;
  Map<int, int> _hourlyEntries = {}; // hour -> count
  List<Map<String, dynamic>> _cameraRanking = [];

  @override
  void initState() {
    super.initState();
    _loadData(_selectedDate);
    
    // Register listener to update reports automatically in real-time
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<TrackingProvider>(context, listen: false)
            .addListener(_onProviderUpdate);
      }
    });
  }

  void _onProviderUpdate() {
    if (mounted) {
      _loadData(_selectedDate, showLoading: false);
    }
  }

  @override
  void dispose() {
    try {
      Provider.of<TrackingProvider>(context, listen: false)
          .removeListener(_onProviderUpdate);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadData(DateTime date, {bool showLoading = true}) async {
    // if showLoading is true, it shows the spinning circle while it gets the data
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    // here we connect to our local sqlite database helper
    final db = DatabaseHelper.instance;

    // we ask the local database for all these stats for the specific day they selected
    final totalTraffic = await db.getTotalTrafficForDate(date);
    final avgDwell = await db.getAvgDwellMinutesForDate(date);
    final hourly = await db.getHourlyEntryCountForDate(date);
    final cameraRanking = await db.getCameraAvgStayForDate(date);

    debugPrint('ReportsScreen: date=$date, totalTraffic=$totalTraffic, hourlyEntries=$hourly');

    if (mounted) {
      setState(() {
        _totalTraffic = totalTraffic;
        _avgDwellMinutes = avgDwell;
        _hourlyEntries = hourly;
        _cameraRanking = cameraRanking;
        if (showLoading) {
          _tappedBarIndex = null;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF5D6AF2),
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E2E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      _selectedDate = picked;
      await _loadData(picked);
    }
  }

  String _formatAvgDwell(double minutes) {
    if (minutes == 0) return '00:00';
    final m = minutes.floor();
    final s = ((minutes - m) * 60).round();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatAvgSeconds(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const Color bg = Color(0xFF0F0F13);
    const Color cardColor = Color(0xFF1A1A24);
    const Color highlightColor = Color(0xFF5D6AF2);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        // if we are waiting for data, show the loading circle in the center.
        // otherwise, show the actual reports!
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D6AF2)))
            : RefreshIndicator(
                // this refreshindicator lets the user pull down on the screen to refresh the data!
                onRefresh: () => _loadData(_selectedDate),
                color: highlightColor,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header Row ──────────────────────────────────
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Reports & Analytics',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _pickDate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today, size: 14, color: highlightColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateFormat('MMM dd, yyyy').format(_selectedDate),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── KPI Cards ───────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _kpiCard(
                              'TOTAL TRAFFIC',
                              '$_totalTraffic',
                              Colors.white,
                              cardColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _kpiCard(
                              'AVG DWELL',
                              _formatAvgDwell(_avgDwellMinutes),
                              highlightColor,
                              cardColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // ── Bar Chart ───────────────────────────────────
                      const Text(
                        'Daily foot traffic (entries per hour)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _totalTraffic == 0
                            ? 'No data recorded for this date'
                            : 'Tap or drag on the graph to see exact count',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),

                      const SizedBox(height: 14),
                      _buildLineChart(cardColor, highlightColor),
                      const SizedBox(height: 28),

                      // ── Zone Occupancy ──────────────────────────────
                      const Text(
                        'Zone occupancy (relative traffic)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildZoneOccupancy(highlightColor),
                      const SizedBox(height: 28),

                      // ── Node Summary ────────────────────────────────
                      const Text(
                        'Hallway stay-time ranking',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Ranked by average time spent per hallway',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      _buildNodeSummary(cardColor, highlightColor),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ─── Line Chart ───────────────────────────────────────────────────────
  Widget _buildLineChart(Color cardColor, Color highlightColor) {
    const double chartHeight = 100.0;
    const double containerHeight = 160.0;

    const int minHour = 8;
    const int maxHour = 20;
    const int range = 12;

    int maxCount = 0;
    for (int h = minHour; h <= maxHour; h++) {
      final c = _hourlyEntries[h] ?? 0;
      if (c > maxCount) maxCount = c;
    }
    if (maxCount == 0) maxCount = 1;

    // layoutbuilder is super cool: it tells us exactly how much width we have to draw on,
    // so our chart can automatically shrink or grow to fit any phone screen size perfectly!
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = constraints.maxWidth - 24; // horizontal padding adjustment
        final stepX = chartWidth / range;
        final selectedHour = _tappedBarIndex?.clamp(minHour, maxHour);

        double? tooltipX;
        double? tooltipY;
        int? tooltipVal;

        if (selectedHour != null && selectedHour >= minHour && selectedHour <= maxHour) {
          tooltipVal = _hourlyEntries[selectedHour] ?? 0;
          tooltipX = (selectedHour - minHour) * stepX + 12; // offset for padding
          tooltipY = chartHeight - (tooltipVal / maxCount) * (chartHeight - 16) - 8;
        }

        void handleTouch(double localX) {
          final adjustedX = (localX - 12).clamp(0.0, chartWidth);
          final hour = (adjustedX / stepX).round() + minHour;
          setState(() {
            _tappedBarIndex = hour.clamp(minHour, maxHour);
          });
        }

        return Container(
          height: containerHeight,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onPanStart: (details) => handleTouch(details.localPosition.dx),
                      onPanUpdate: (details) => handleTouch(details.localPosition.dx),
                      onTapDown: (details) => handleTouch(details.localPosition.dx),
                      child: Container(
                        color: Colors.transparent, // target gesture detector
                        child: CustomPaint(
                          painter: LineChartPainter(
                            hourlyEntries: _hourlyEntries,
                            lineColor: highlightColor,
                            gridColor: Colors.white.withAlpha(12),
                            selectedHour: selectedHour,
                            minHour: minHour,
                            maxHour: maxHour,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildLineChartLabels(chartWidth, minHour, maxHour),
                ],
              ),
              if (tooltipX != null && tooltipY != null && tooltipVal != null)
                Positioned(
                  left: (tooltipX - 35).clamp(4.0, constraints.maxWidth - 74),
                  top: (tooltipY - 32).clamp(-10.0, containerHeight),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Text(
                      '${selectedHour.toString().padLeft(2, '0')}:00 → $tooltipVal',
                      style: TextStyle(
                        color: cardColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLineChartLabels(double chartWidth, int minHour, int maxHour) {
    const labelHours = [8, 11, 14, 17, 20];
    final stepX = chartWidth / 12;
    return Container(
      height: 12,
      margin: const EdgeInsets.only(top: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: labelHours.map((h) {
          final label = '${h.toString().padLeft(2, '0')}:00';
          final left = (h - minHour) * stepX + 12 - 15; // align center
          return Positioned(
            left: left.clamp(0.0, chartWidth - 10),
            child: SizedBox(
              width: 30,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 8),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }


  // ─── Zone Occupancy ───────────────────────────────────────────────────
  Widget _buildZoneOccupancy(Color highlightColor) {
    // Derive relative occupancy from the camera ranking avg seconds
    final maxSeconds = _cameraRanking.fold<int>(
      1,
      (m, e) => (e['avgSeconds'] as int) > m ? (e['avgSeconds'] as int) : m,
    );

    // Build in fixed hallway order (1→4) for consistency
    final sorted = List.generate(4, (i) {
      final name = 'Hallway ${i + 1} Camera';
      final match = _cameraRanking.firstWhere(
        (e) => e['name'] == name,
        orElse: () => {'name': name, 'avgSeconds': 0},
      );
      return match;
    });

    return Column(
      children: sorted.map((entry) {
        final avg = entry['avgSeconds'] as int;
        final pct = maxSeconds > 0 ? avg / maxSeconds : 0.0;
        final displayName = (entry['name'] as String).replaceAll(' Camera', '');
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  Text(
                    avg > 0 ? 'avg ${_formatAvgSeconds(avg)}' : 'No data',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.white10,
                color: highlightColor,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── Node Ranking ─────────────────────────────────────────────────────
  Widget _buildNodeSummary(Color cardColor, Color highlightColor) {
    if (_cameraRanking.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No data for this date.', style: TextStyle(color: Colors.white38)),
      );
    }
    return Column(
      children: List.generate(_cameraRanking.length, (i) {
        final node = _cameraRanking[i];
        final avg = node['avgSeconds'] as int;
        final rankColor = i == 0
            ? const Color(0xFFFFD700)  // Gold
            : i == 1
                ? const Color(0xFFC0C0C0) // Silver
                : i == 2
                    ? const Color(0xFFCD7F32) // Bronze
                    : Colors.white38;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: i == 0 ? const Color(0xFFFFD700).withAlpha(80) : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              Text(
                '#${i + 1}',
                style: TextStyle(
                  color: rankColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  node['name'] as String,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                avg > 0 ? 'avg ${_formatAvgSeconds(avg)}' : 'No data',
                style: TextStyle(
                  color: avg > 0 ? Colors.white54 : Colors.white24,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ─── KPI card ─────────────────────────────────────────────────────────
  Widget _kpiCard(String title, String value, Color valueColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 30, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final Map<int, int> hourlyEntries;
  final Color lineColor;
  final Color gridColor;
  final int? selectedHour;
  final int minHour;
  final int maxHour;

  LineChartPainter({
    required this.hourlyEntries,
    required this.lineColor,
    required this.gridColor,
    this.selectedHour,
    required this.minHour,
    required this.maxHour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;

    // Find max value
    int maxVal = 0;
    for (int h = minHour; h <= maxHour; h++) {
      final val = hourlyEntries[h] ?? 0;
      if (val > maxVal) maxVal = val;
    }
    if (maxVal == 0) maxVal = 1;

    final range = maxHour - minHour;
    final double stepX = width / (range == 0 ? 1 : range);

    double getX(int hour) => (hour - minHour) * stepX;
    double getY(int hour) {
      final count = hourlyEntries[hour] ?? 0;
      return height - (count / maxVal) * (height - 16) - 8; // margins top and bottom
    }

    // 1. Draw grid lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (int i = 1; i <= 3; i++) {
      final y = height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    // 2. Draw line and fill area
    final path = Path();
    final fillPath = Path();

    path.moveTo(getX(minHour), getY(minHour));
    fillPath.moveTo(getX(minHour), height);
    fillPath.lineTo(getX(minHour), getY(minHour));

    for (int h = minHour + 1; h <= maxHour; h++) {
      final x = getX(h);
      final y = getY(h);
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(width, height);
    fillPath.close();

    // Fill gradient
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withAlpha(50),
          lineColor.withAlpha(0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height));
    canvas.drawPath(fillPath, fillPaint);

    // Stroke line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // 3. Draw vertical selection line & highlight dot
    if (selectedHour != null && selectedHour! >= minHour && selectedHour! <= maxHour) {
      final selX = getX(selectedHour!);
      final selY = getY(selectedHour!);

      final selectLinePaint = Paint()
        ..color = lineColor.withAlpha(100)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      
      // Draw vertical line from top to bottom
      canvas.drawLine(Offset(selX, 0), Offset(selX, height), selectLinePaint);

      // Draw outer indicator ring
      final ringPaint = Paint()
        ..color = lineColor.withAlpha(60)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(selX, selY), 8, ringPaint);

      // Draw dot
      final dotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(selX, selY), 4, dotPaint);

      final dotOutline = Paint()
        ..color = lineColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(selX, selY), 4, dotOutline);
    } else {
      // Draw small dot on hours that have data to guide user
      final dotPaint = Paint()
        ..color = lineColor.withAlpha(150)
        ..style = PaintingStyle.fill;
      for (int h = minHour; h <= maxHour; h++) {
        final count = hourlyEntries[h] ?? 0;
        if (count > 0) {
          canvas.drawCircle(Offset(getX(h), getY(h)), 3, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) {
    return oldDelegate.hourlyEntries != hourlyEntries ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.selectedHour != selectedHour ||
        oldDelegate.minHour != minHour ||
        oldDelegate.maxHour != maxHour;
  }
}

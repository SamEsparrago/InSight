import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'login_screen.dart';
import 'reports_screen.dart';
import 'repository/tracking_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

class NoStretchScrollBehavior extends ScrollBehavior {
  const NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child; // Completely disables the Android overscroll glow/stretch effect
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // ClampingScrollPhysics prevents bouncing, giving a "static block" hard-stop feel.
    return const ClampingScrollPhysics();
  }
}

Future<void> main() async {
  // this is where the app actually starts running!
  // first, we make sure flutter is ready to draw stuff on the screen.
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // here is where we connect to firebase! 
    // it uses the firebase_options.dart file we generated earlier to know which project to connect to.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase initialization failed/unsupported: $e");
  }

  final repository = SyncedTrackingRepository();
  // before showing the ui, we load up any saved data from the local sqlite database
  // so the app works even if the internet is slow or off right now.
  await repository
      .loadPersistedPeople(); // Restore active people from SQLite on startup

  // runApp is the flutter command to start the app.
  // we wrap the whole app in a 'provider'. think of a provider like a giant backpack
  // that holds all our live tracking data. any screen inside the app can just reach into 
  // the backpack to get the latest info without passing it down manually.
  runApp(
    ChangeNotifierProvider(
      create: (_) => TrackingProvider(repository: repository),
      child: const MultiCamTrackingApp(),
    ),
  );
}

class MultiCamTrackingApp extends StatelessWidget {
  const MultiCamTrackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CrowdTrack Dashboard',
      scrollBehavior: const NoStretchScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Modern Indigo Accent
          brightness: Brightness.dark, // Sleek Dark Theme UI
          surface: const Color(0xFF1E1E2E),
          background: const Color(0xFF121214),
        ),
        cardTheme: const CardThemeData(color: Color(0xFF252538), elevation: 0),
      ),
      home: const LoginScreen(),
    );
  }
}

// ==========================================
// 1. DATA MODELS
// ==========================================
class CameraLog {
  final String status;
  final DateTime timestamp;

  CameraLog(this.status, this.timestamp);
}

class TrackedPerson {
  final String id;
  final DateTime entryTime;
  DateTime? exitTime;
  int currentCamera; // 1, 2, 3, 4, or 0 if exited
  List<CameraLog> history;

  TrackedPerson({
    required this.id,
    required this.entryTime,
    this.exitTime,
    required this.currentCamera,
    required this.history,
  });

  // Calculate local time elapsed since initial entry
  Duration get totalStayDuration {
    final end = exitTime ?? DateTime.now();
    return end.difference(entryTime);
  }
}

// ==========================================
// 2. STATE MANAGEMENT & SIMULATION LOGIC
// ==========================================
class TrackingProvider extends ChangeNotifier {
  final TrackingRepository repository;

  TrackingProvider({required this.repository}) {
    repository.onExternalDataSync = () {
      notifyListeners();
    };
  }

  bool _isAutoSimulating = false;
  Timer? _simulationTimer;
  final Random _random = Random();

  int _targetSpawnsThisMinute = 3;
  DateTime? _minuteStartTime;
  List<int> _spawnTickOffsets = [];
  int _tickCount = 0;
  final Map<String, int> _targetStays = {};

  List<TrackedPerson> get people => repository.people;
  bool get isAutoSimulating => _isAutoSimulating;

  // Global Metrics Getters
  int get currentOccupancy => people.where((p) => p.currentCamera > 0).length;
  int get totalEntries {
    final now = DateTime.now();
    return people.where((p) {
      return p.entryTime.year == now.year &&
          p.entryTime.month == now.month &&
          p.entryTime.day == now.day;
    }).length;
  }

  Duration get averageStayTime {
    final exitedPeople = people.where((p) => p.exitTime != null).toList();
    if (exitedPeople.isEmpty) return Duration.zero;

    final totalDuration = exitedPeople.fold<Duration>(
      Duration.zero,
      (prev, element) => prev + element.exitTime!.difference(element.entryTime),
    );
    return Duration(
      milliseconds: totalDuration.inMilliseconds ~/ exitedPeople.length,
    );
  }

  // Get count of people inside a specific camera unit
  int getCameraCount(int camNum) {
    return people.where((p) => p.currentCamera == camNum).length;
  }

  // Action: Add new entry to Cam 1
  void simulateNewEntry() {
    if (currentOccupancy >= 100) return;
    // Generate a random 6-character uppercase alphanumeric ID (e.g., #A8F9X2)
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final randomStr = String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(_random.nextInt(chars.length))),
    );
    final newId = '#$randomStr';
    final now = DateTime.now();

    final newPerson = TrackedPerson(
      id: newId,
      entryTime: now,
      currentCamera: 1,
      history: [CameraLog('Detected at Hallway 1 Camera (Entrance)', now)],
    );
    repository.addPerson(newPerson);
    notifyListeners();
  }

  // Action: Cascade movement to next camera section
  void movePersonToNextCamera(String id) {
    final personIndex = people.indexWhere((p) => p.id == id);
    if (personIndex == -1) return;

    final person = people[personIndex];
    final now = DateTime.now();

    if (person.currentCamera < 4 && person.currentCamera > 0) {
      person.currentCamera += 1;
      person.history.add(
        CameraLog('Passed to Hallway ${person.currentCamera} Camera', now),
      );
    } else if (person.currentCamera == 4) {
      person.currentCamera = 0;
      person.exitTime = now;
      person.history
          .add(CameraLog('Exited Facility through Hallway 4 Camera', now));
      _targetStays.remove(person.id);
    }

    repository.updatePerson(person);
    notifyListeners();
  }

  // Toggle Auto Engine Loop
  void toggleAutoSimulation() {
    _isAutoSimulating = !_isAutoSimulating;
    if (_isAutoSimulating) {
      _minuteStartTime = null; // Forces recalculation on first step
      _tickCount = 0;
      _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        _runAutomaticStep();
      });
    } else {
      _simulationTimer?.cancel();
    }
    notifyListeners();
  }

  void _runAutomaticStep() {
    final now = DateTime.now();

    // 1. Initialize or reset the minute block
    if (_minuteStartTime == null ||
        now.difference(_minuteStartTime!) >= const Duration(minutes: 1)) {
      _minuteStartTime = now;
      _targetSpawnsThisMinute =
          1 + _random.nextInt(5); // 1-5 customers per minute
      _tickCount = 0;

      // Select _targetSpawnsThisMinute unique random ticks from 0 to 29
      final List<int> offsets = List.generate(30, (i) => i);
      offsets.shuffle(_random);
      _spawnTickOffsets = offsets.take(_targetSpawnsThisMinute).toList();
    }

    // 2. Check if we should spawn a customer at this tick
    if (_spawnTickOffsets.contains(_tickCount)) {
      // Check if we are below the maximum of 100
      if (currentOccupancy < 100) {
        simulateNewEntry();
      }
    }
    _tickCount++;

    // 3. Update existing customers' locations based on their stay duration (1-2 mins)
    final activePeople = people.where((p) => p.currentCamera > 0).toList();
    bool updatedAny = false;

    for (final person in activePeople) {
      final totalStay = _targetStays[person.id] ??=
          (60 + _random.nextInt(61)); // 60 to 120 seconds
      final elapsed = now.difference(person.entryTime).inSeconds;

      int targetCam;
      if (elapsed >= totalStay) {
        targetCam = 0;
      } else if (elapsed >= (3 * totalStay) ~/ 4) {
        targetCam = 4;
      } else if (elapsed >= (2 * totalStay) ~/ 4) {
        targetCam = 3;
      } else if (elapsed >= totalStay ~/ 4) {
        targetCam = 2;
      } else {
        targetCam = 1;
      }

      if (targetCam != person.currentCamera) {
        if (targetCam == 0) {
          person.currentCamera = 0;
          person.exitTime = now;
          person.history
              .add(CameraLog('Exited Facility through Hallway 4 Camera', now));
          _targetStays.remove(person.id);
        } else {
          person.currentCamera = targetCam;
          person.history.add(
            CameraLog('Passed to Hallway $targetCam Camera', now),
          );
        }
        repository.updatePerson(person);
        updatedAny = true;
      }
    }

    if (updatedAny) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }
}

// ==========================================
// 3. MAIN APP INTERFACE ARCHITECTURE
// ==========================================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  // this variable remembers which tab is currently selected (0 is the first tab)
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Re-trigger Firestore sync after successful login to pull past data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<TrackingProvider>(context, listen: false)
            .repository
            .loadPersistedPeople();
      }
    });
  }

  // these are the 4 main screens of our app!
  final List<Widget> _tabs = [
    const DashboardTab(),
    const CameraSectionsTab(),
    const ReportsScreen(), // NEW TAB
    const SimulatorTab(),
  ];

  @override
  Widget build(BuildContext context) {
    // scaffold is a basic flutter layout structure that gives us a blank canvas
    return Scaffold(
      // safe area makes sure the app doesn't draw over the phone's notch or status bar
      body: SafeArea(child: _tabs[_currentIndex]),
      
      // this is the bottom navigation bar you see on the app.
      // it handles switching between the 4 screens.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          // setState tells flutter to redraw the screen because something changed!
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'Cameras',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Simulator',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// CCTV HORIZONTAL FEED AND MODAL WIDGETS
// ==========================================
class CCTVFeedCard extends StatelessWidget {
  final int camNum;
  final String cameraName;

  const CCTVFeedCard({
    super.key,
    required this.camNum,
    required this.cameraName,
  });

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TrackingProvider>(context);
    final count = provider.getCameraCount(camNum);

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => _CCTVFeedModal(
            camNum: camNum,
            cameraName: cameraName,
          ),
        );
      },
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          image: DecorationImage(
            image: AssetImage('assets/camera $camNum.png'),
            fit: BoxFit.cover,
            onError: (exception, stackTrace) {
              debugPrint('Error loading camera image: $exception');
            },
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.8),
              ],
            ),
          ),
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top HUD Layer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white24, width: 0.5),
                    ),
                    child: Text(
                      cameraName,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: count > 0
                          ? Colors.red.withValues(alpha: 0.8)
                          : Colors.green.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.fiber_manual_record,
                          color: count > 0 ? Colors.white : Colors.greenAccent,
                          size: 10,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE [$count]',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
              // Bottom HUD Layer
              Align(
                alignment: Alignment.bottomRight,
                child: StreamBuilder(
                  stream: Stream.periodic(const Duration(seconds: 1)),
                  builder: (context, snapshot) {
                    final now = DateTime.now();
                    final timeStr =
                        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                    return Text(
                      timeStr,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                        shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CCTVFeedModal extends StatelessWidget {
  final int camNum;
  final String cameraName;

  const _CCTVFeedModal({
    super.key,
    required this.camNum,
    required this.cameraName,
  });

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TrackingProvider>(context);
    final peopleInCam =
        provider.people.where((p) => p.currentCamera == camNum).toList();
    final count = peopleInCam.length;

    // Calculate Dwell Duration
    Duration avgDwell = Duration.zero;
    if (peopleInCam.isNotEmpty) {
      final totalSeconds = peopleInCam.fold<int>(
          0, (prev, p) => prev + p.totalStayDuration.inSeconds);
      avgDwell = Duration(seconds: totalSeconds ~/ peopleInCam.length);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle for bottom sheet
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Scaled Viewport
            SizedBox(
              height: 220,
              width: double.infinity,
              child: CCTVFeedCard(camNum: camNum, cameraName: cameraName),
            ),
            const SizedBox(height: 24),
            const Text(
              'Live Analytics',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252538),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Occupancy',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text('$count',
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252538),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Avg Dwell Time',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text('${avgDwell.inSeconds}s',
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Dismiss',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: peopleInCam.isEmpty
                        ? null
                        : () {
                            // Find oldest person (longest stay)
                            peopleInCam.sort((a, b) => b
                                .totalStayDuration.inSeconds
                                .compareTo(a.totalStayDuration.inSeconds));
                            final oldest = peopleInCam.first;
                            provider.movePersonToNextCamera(oldest.id);
                            Navigator.pop(context);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigoAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Force Transition',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// TAB 1: DASHBOARD VISUAL ENGINE
// ==========================================
class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TrackingProvider>(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'System Overview',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Live operational state metric layers',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white70),
                tooltip: 'Logout',
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Core KPI Layout Grid
          Row(
            children: [
              Expanded(
                child: _buildKPICard(
                  title: 'Inside Structure',
                  value: '${provider.currentOccupancy} / 100',
                  icon: Icons.meeting_room,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKPICard(
                  title: 'Total Traffic',
                  value: '${provider.totalEntries}',
                  icon: Icons.group,
                  color: Colors.indigoAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Live Node Monitoring',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              itemBuilder: (context, index) {
                final camNum = index + 1;
                final names = [
                  'HALLWAY 1',
                  'HALLWAY 2',
                  'MAIN LOBBY',
                  'EXIT GATE'
                ];
                return Padding(
                  padding: EdgeInsets.only(
                    right: 16.0,
                    top: index % 2 == 1 ? 24.0 : 0.0, // Staggered effect
                    bottom: index % 2 == 0 ? 24.0 : 0.0,
                  ),
                  child: CCTVFeedCard(
                    camNum: camNum,
                    cameraName: 'CAM 0$camNum // ${names[index]}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isWide = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252538),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment:
            isWide ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (isWide) const SizedBox() else const Spacer(),
          Icon(icon, color: color, size: 32),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 2: CAMERA SWITCHER GRID LAYOUT
// ==========================================
class CameraSectionsTab extends StatefulWidget {
  const CameraSectionsTab({super.key});

  @override
  State<CameraSectionsTab> createState() => _CameraSectionsTabState();
}

class _CameraSectionsTabState extends State<CameraSectionsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TrackingProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hardware Nodes',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Section monitoring feed logs',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),

        // Horizontal Custom Tab Bar Switching Node Channels
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: List.generate(4, (index) {
            final camNum = index + 1;
            final count = provider.getCameraCount(camNum);
            return Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Hallway $camNum'),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.indigoAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ),

        // Active Node Display Grid View Area
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: List.generate(4, (index) {
              final camNum = index + 1;
              final peopleInCam = provider.people
                  .where((p) => p.currentCamera == camNum)
                  .toList();

              if (peopleInCam.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.center_focus_weak,
                        size: 48,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No profiles tracked in Hallway $camNum',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.3,
                ),
                itemCount: peopleInCam.length,
                itemBuilder: (context, idx) {
                  final person = peopleInCam[idx];
                  return GestureDetector(
                    onTap: () => _showAuditTimeline(context, person),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF252538),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                person.id,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigoAccent,
                                ),
                              ),
                              const Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Time Inside:',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                '${person.totalStayDuration.inSeconds}s elapsed',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ),
      ],
    );
  }

  // Pop up showing the absolute history log transitions
  void _showAuditTimeline(BuildContext context, TrackedPerson person) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lifecycle Audit Log: ${person.id}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: person.history.length,
                  itemBuilder: (context, index) {
                    final log = person.history[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.subdirectory_arrow_right,
                        color: Colors.indigoAccent,
                      ),
                      title: Text(log.status),
                      subtitle: Text(
                        '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// TAB 3: SYSTEM CONTROL PANEL & ENGINE SIMULATOR
// ==========================================
class SimulatorTab extends StatelessWidget {
  const SimulatorTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TrackingProvider>(context);
    final activePeople =
        provider.people.where((p) => p.currentCamera > 0).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Simulation Panel',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Control tracking states manually or execute automated pipelines',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),

          // Automation Toggle Row Switch
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: provider.isAutoSimulating
                  ? Colors.indigo.withValues(alpha: 0.2)
                  : const Color(0xFF252538),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: provider.isAutoSimulating
                    ? Colors.indigoAccent
                    : Colors.white10,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      provider.isAutoSimulating
                          ? Icons.autorenew
                          : Icons.motion_photos_off,
                      color: provider.isAutoSimulating
                          ? Colors.indigoAccent
                          : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Auto-Simulation Engine',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          provider.isAutoSimulating
                              ? 'Engine cycling active data ticks...'
                              : 'Engine execution standing by',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Switch(
                  value: provider.isAutoSimulating,
                  onChanged: (_) => provider.toggleAutoSimulation(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Manual Entry Trigger
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed:
                  provider.isAutoSimulating || provider.currentOccupancy >= 100
                      ? null
                      : () => provider.simulateNewEntry(),
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Simulate New Entry (Spawn @ Hallway 1)'),
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Active Tracking Node Controls',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // List view mapping out actionable individuals inside the structure
          Expanded(
            child: activePeople.isEmpty
                ? Center(
                    child: Text(
                      'No entities active. Turn on auto-simulation or spawn manually.',
                      style: TextStyle(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: activePeople.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final person = activePeople[index];
                      final isLastCam = person.currentCamera == 4;

                      return ListTile(
                        tileColor: const Color(0xFF252538),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: Text(
                          person.id,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigoAccent,
                          ),
                        ),
                        subtitle: Text(
                          'Currently active inside Hallway ${person.currentCamera} Camera',
                        ),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLastCam
                                ? Colors.redAccent.withValues(alpha: 0.2)
                                : Colors.white10,
                            foregroundColor:
                                isLastCam ? Colors.redAccent : Colors.white,
                            elevation: 0,
                          ),
                          onPressed: provider.isAutoSimulating
                              ? null
                              : () =>
                                  provider.movePersonToNextCamera(person.id),
                          icon: Icon(
                            isLastCam ? Icons.logout : Icons.arrow_forward,
                          ),
                          label: Text(isLastCam ? 'Exit' : 'Next Zone'),
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

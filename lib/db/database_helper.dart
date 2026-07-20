import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _db;

  DatabaseHelper._internal();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._internal();
    return _instance!;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    // since flutter works on web, desktop, and mobile, this tells the database exactly how to start
    // depending on the platform it's currently running on.
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'insight_tracking.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // this runs the very first time the app is ever opened on the phone.
    // it creates the two tables where we store our tracking data offline using sql code!
    
    // table 1: tracking individual people
    await db.execute('''
      CREATE TABLE tracked_persons (
        id TEXT PRIMARY KEY,
        entry_time INTEGER NOT NULL,
        exit_time INTEGER,
        current_camera INTEGER NOT NULL DEFAULT 1,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // table 2: the history of every camera they pass through
    await db.execute('''
      CREATE TABLE camera_logs (
        log_id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id TEXT NOT NULL,
        status TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (person_id) REFERENCES tracked_persons(id)
      )
    ''');

    // Index for fast date-range queries on logs
    await db.execute('''
      CREATE INDEX idx_camera_logs_timestamp ON camera_logs(timestamp)
    ''');
    await db.execute('''
      CREATE INDEX idx_tracked_persons_entry ON tracked_persons(entry_time)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final columns = await db.rawQuery('PRAGMA table_info(tracked_persons)');
      final hasSynced = columns.any((column) => column['name'] == 'synced');
      if (!hasSynced) {
        await db.execute(
          'ALTER TABLE tracked_persons ADD COLUMN synced INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
  }

  // ─── WRITE OPERATIONS ─────────────────────────────────────────

  Future<void> insertPerson({
    required String id,
    required DateTime entryTime,
    required int currentCamera,
    int synced = 0,
  }) async {
    final db = await database;
    await db.insert(
      'tracked_persons',
      {
        'id': id,
        'entry_time': entryTime.millisecondsSinceEpoch,
        'exit_time': null,
        'current_camera': currentCamera,
        'synced': synced,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updatePersonCamera({
    required String id,
    required int currentCamera,
    DateTime? exitTime,
    int synced = 0,
  }) async {
    final db = await database;
    await db.update(
      'tracked_persons',
      {
        'current_camera': currentCamera,
        'exit_time': exitTime?.millisecondsSinceEpoch,
        'synced': synced,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertLog({
    required String personId,
    required String status,
    required DateTime timestamp,
  }) async {
    final db = await database;
    await db.insert('camera_logs', {
      'person_id': personId,
      'status': status,
      'timestamp': timestamp.millisecondsSinceEpoch,
    });
  }

  Future<void> upsertPersonWithLogs({
    required String id,
    required DateTime entryTime,
    DateTime? exitTime,
    required int currentCamera,
    required List<Map<String, dynamic>> logs,
    int synced = 1,
  }) async {
    final db = await database;
    
    // we use a transaction here. a transaction is like an all-or-nothing guarantee.
    // if the phone crashes in the middle of this block, it throws everything out,
    // so we never end up with half-saved or corrupted data!
    await db.transaction((txn) async {
      await txn.insert(
        'tracked_persons',
        {
          'id': id,
          'entry_time': entryTime.millisecondsSinceEpoch,
          'exit_time': exitTime?.millisecondsSinceEpoch,
          'current_camera': currentCamera,
          'synced': synced,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'camera_logs',
        where: 'person_id = ?',
        whereArgs: [id],
      );

      for (final log in logs) {
        await txn.insert('camera_logs', {
          'person_id': id,
          'status': log['status'],
          'timestamp': (log['timestamp'] as DateTime).millisecondsSinceEpoch,
        });
      }
    });
  }

  Future<void> markSynced(String id) async {
    final db = await database;
    await db.update(
      'tracked_persons',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedPeople() async {
    final db = await database;
    return db.query(
      'tracked_persons',
      where: 'synced = 0',
    );
  }

  // ─── READ OPERATIONS ─────────────────────────────────────────

  /// Returns a map of hour (0–23) → count of entries in that hour for the given date.
  Future<Map<int, int>> getHourlyEntryCountForDate(DateTime date) async {
    final db = await database;

    final dayStart = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch;

    final rows = await db.query(
      'tracked_persons',
      where: 'entry_time BETWEEN ? AND ?',
      whereArgs: [dayStart, dayEnd],
    );

    final Map<int, int> hourly = {};
    for (final row in rows) {
      final dt = DateTime.fromMillisecondsSinceEpoch(row['entry_time'] as int);
      final hour = dt.hour;
      hourly[hour] = (hourly[hour] ?? 0) + 1;
    }
    return hourly;
  }

  /// Returns total count of entries for the given date.
  Future<int> getTotalTrafficForDate(DateTime date) async {
    final db = await database;
    final dayStart = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM tracked_persons WHERE entry_time BETWEEN ? AND ?',
      [dayStart, dayEnd],
    );
    return (result.first['cnt'] as int? ?? 0);
  }

  /// Returns average stay duration (in minutes) for people who exited on the given date.
  Future<double> getAvgDwellMinutesForDate(DateTime date) async {
    final db = await database;
    final dayStart = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch;

    final rows = await db.query(
      'tracked_persons',
      where: 'exit_time IS NOT NULL AND exit_time BETWEEN ? AND ?',
      whereArgs: [dayStart, dayEnd],
    );

    if (rows.isEmpty) return 0.0;

    double totalMs = 0;
    for (final row in rows) {
      final entry = row['entry_time'] as int;
      final exit = row['exit_time'] as int;
      totalMs += (exit - entry).toDouble();
    }
    return (totalMs / rows.length) / 60000.0; // convert to minutes
  }

  /// Returns per-camera average stay time in seconds for a given date.
  /// Returns a list of {name, avgSeconds} sorted by avgSeconds descending.
  Future<List<Map<String, dynamic>>> getCameraAvgStayForDate(DateTime date) async {
    final db = await database;
    final dayStart = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch;

    // Get all camera_logs for people who entered on this date
    final persons = await db.query(
      'tracked_persons',
      where: 'entry_time BETWEEN ? AND ?',
      whereArgs: [dayStart, dayEnd],
    );

    if (persons.isEmpty) {
      return List.generate(4, (i) => {'name': 'Hallway ${i + 1} Camera', 'avgSeconds': 0});
    }

    // For each camera (1–4), calculate how long people spent there
    // We approximate by looking at consecutive log entries per person
    final Map<int, List<int>> cameraSeconds = {1: [], 2: [], 3: [], 4: []};

    for (final person in persons) {
      final personId = person['id'] as String;
      final logs = await db.query(
        'camera_logs',
        where: 'person_id = ?',
        whereArgs: [personId],
        orderBy: 'timestamp ASC',
      );

      for (int i = 0; i < logs.length - 1; i++) {
        final current = logs[i];
        final next = logs[i + 1];
        final status = current['status'] as String;
        int camNum = 0;
        for (int c = 1; c <= 4; c++) {
          if (status.contains('Hallway $c') || status.contains('Camera $c')) {
            camNum = c;
            break;
          }
        }
        if (camNum > 0) {
          final durMs = (next['timestamp'] as int) - (current['timestamp'] as int);
          if (durMs > 0) cameraSeconds[camNum]!.add(durMs ~/ 1000);
        }
      }
    }

    final result = <Map<String, dynamic>>[];
    for (int c = 1; c <= 4; c++) {
      final times = cameraSeconds[c]!;
      final avg = times.isEmpty ? 0 : times.reduce((a, b) => a + b) ~/ times.length;
      result.add({'name': 'Hallway $c Camera', 'avgSeconds': avg});
    }
    result.sort((a, b) => (b['avgSeconds'] as int).compareTo(a['avgSeconds'] as int));
    return result;
  }

  /// Returns all persons currently tracked (not exited) — used to restore state on app restart.
  Future<List<Map<String, dynamic>>> getActivePeople() async {
    final db = await database;
    return db.query(
      'tracked_persons',
      where: 'current_camera > 0',
    );
  }

  /// Returns all logs for a specific person.
  Future<List<Map<String, dynamic>>> getLogsForPerson(String personId) async {
    final db = await database;
    return db.query(
      'camera_logs',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'timestamp ASC',
    );
  }
}

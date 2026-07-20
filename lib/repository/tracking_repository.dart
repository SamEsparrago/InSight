import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../main.dart'; // For TrackedPerson & CameraLog
import '../db/database_helper.dart';

/// Abstract base class for the data layer.
/// Swap MockRepository for SqliteRepository, later swap for FirestoreRepository.
abstract class TrackingRepository {
  List<TrackedPerson> get people;
  void addPerson(TrackedPerson person);
  void updatePerson(TrackedPerson person);
  Future<void> loadPersistedPeople(); // Restore state from DB on startup
  VoidCallback? onExternalDataSync;
}

// ─── MOCK (in-memory, no persistence) ─────────────────────────────────
class MockTrackingRepository implements TrackingRepository {
  final List<TrackedPerson> _people = [];

  @override
  VoidCallback? onExternalDataSync;

  @override
  List<TrackedPerson> get people => _people;

  @override
  void addPerson(TrackedPerson person) {
    _people.add(person);
  }

  @override
  void updatePerson(TrackedPerson person) {
    final index = _people.indexWhere((p) => p.id == person.id);
    if (index != -1) _people[index] = person;
  }

  @override
  Future<void> loadPersistedPeople() async {} // No-op for mock
}

// ─── SQLITE (offline persistence) ─────────────────────────────────────
class SqliteTrackingRepository implements TrackingRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final List<TrackedPerson> _people = [];

  @override
  VoidCallback? onExternalDataSync;

  @override
  List<TrackedPerson> get people => _people;

  /// Call once on startup to restore active people from SQLite.
  @override
  Future<void> loadPersistedPeople() async {
    _people.clear();
    final rows = await _db.getActivePeople();
    for (final row in rows) {
      final id = row['id'] as String;
      final logs = await _db.getLogsForPerson(id);
      final history = logs
          .map((l) => CameraLog(
                l['status'] as String,
                DateTime.fromMillisecondsSinceEpoch(l['timestamp'] as int),
              ))
          .toList();

      _people.add(TrackedPerson(
        id: id,
        entryTime: DateTime.fromMillisecondsSinceEpoch(row['entry_time'] as int),
        exitTime: row['exit_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['exit_time'] as int)
            : null,
        currentCamera: row['current_camera'] as int,
        history: history,
      ));
    }
  }

  @override
  void addPerson(TrackedPerson person) {
    _people.add(person);
    // Fire-and-forget write to SQLite
    _db.insertPerson(
      id: person.id,
      entryTime: person.entryTime,
      currentCamera: person.currentCamera,
    );
    for (final log in person.history) {
      _db.insertLog(
        personId: person.id,
        status: log.status,
        timestamp: log.timestamp,
      );
    }
  }

  @override
  void updatePerson(TrackedPerson person) {
    final index = _people.indexWhere((p) => p.id == person.id);
    if (index != -1) _people[index] = person;

    // Persist camera movement and new log entry
    _db.updatePersonCamera(
      id: person.id,
      currentCamera: person.currentCamera,
      exitTime: person.exitTime,
    );
    // Save the latest log entry only
    if (person.history.isNotEmpty) {
      final latest = person.history.last;
      _db.insertLog(
        personId: person.id,
        status: latest.status,
        timestamp: latest.timestamp,
      );
    }
  }
}

// ─── SYNCED (Offline-first: SQLite + Firestore) ───────────────────────
class SyncedTrackingRepository implements TrackingRepository {
  final SqliteTrackingRepository _sqliteRepo = SqliteTrackingRepository();
  dynamic _snapshotSub; // To hold the stream subscription and prevent duplicates

  // Safely get Firestore only if Firebase was successfully initialized
  FirebaseFirestore? get _firestore {
    if (Firebase.apps.isNotEmpty) {
      return FirebaseFirestore.instance;
    }
    return null;
  }

  @override
  List<TrackedPerson> get people => _sqliteRepo.people;

  @override
  VoidCallback? onExternalDataSync;

  @override
  Future<void> loadPersistedPeople() async {
    // 1. instantly load from local sqlite database first!
    // this means the app is instantly ready to use even if the internet is down right now.
    await _sqliteRepo.loadPersistedPeople();

    final firestore = _firestore;
    if (firestore == null) {
      debugPrint("❌ SyncedTrackingRepository: FirebaseFirestore is NULL. Firebase.apps.isNotEmpty = ${Firebase.apps.isNotEmpty}");
      return;
    }

    debugPrint("🔄 SyncedTrackingRepository: Setting up Firestore snapshots listener on 'tracked_persons'...");

    // Helper function to safely parse DateTime from Firestore (handles Strings, Timestamps, etc.)
    DateTime? safeParseDateTime(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    // Cancel existing subscription if re-initializing (e.g., after login)
    _snapshotSub?.cancel();

    // 2. set up a live listener to firestore
    // this keeps checking the internet for any new data from the cloud and syncs it down to our local database
    _snapshotSub = firestore.collection('tracked_persons').snapshots().listen((snapshot) async {
      debugPrint("📥 SyncedTrackingRepository: Received Firestore snapshot with ${snapshot.docs.length} documents. docChanges length = ${snapshot.docChanges.length}");
      bool localUpdateNeeded = false;

      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data == null) continue;

          final id = data['id']?.toString() ?? '';
          final entryTime = safeParseDateTime(data['entryTime']) ?? DateTime.now();
          final exitTime = safeParseDateTime(data['exitTime']);
          final currentCamera = (data['currentCamera'] as num?)?.toInt() ?? 1;
          
          final historyList = (data['history'] as List<dynamic>?) ?? [];
          final List<Map<String, dynamic>> logs = [];
          for (final l in historyList) {
            if (l is Map) {
              final status = l['status']?.toString() ?? 'Unknown';
              final timestamp = safeParseDateTime(l['timestamp']) ?? DateTime.now();
              logs.add({
                'status': status,
                'timestamp': timestamp,
              });
            }
          }

          debugPrint("💾 SyncedTrackingRepository: Syncing doc $id (entryTime: $entryTime, camera: $currentCamera) to SQLite");

          // 1. Sync to local SQLite
          await _sqliteRepo._db.upsertPersonWithLogs(
            id: id,
            entryTime: entryTime,
            exitTime: exitTime,
            currentCamera: currentCamera,
            logs: logs,
          );

          // 2. Update in-memory state
          final person = TrackedPerson(
            id: id,
            entryTime: entryTime,
            exitTime: exitTime,
            currentCamera: currentCamera,
            history: logs.map((l) => CameraLog(l['status'] as String, l['timestamp'] as DateTime)).toList(),
          );

          final index = _sqliteRepo._people.indexWhere((p) => p.id == id);
          if (index != -1) {
            _sqliteRepo._people[index] = person;
          } else {
            _sqliteRepo._people.add(person);
          }

          localUpdateNeeded = true;
        }
      }

      if (localUpdateNeeded && onExternalDataSync != null) {
        debugPrint("🔔 SyncedTrackingRepository: Data synced from Firestore, notifying listeners.");
        onExternalDataSync!();
      }
    }, onError: (e) {
      debugPrint("❌ SyncedTrackingRepository Firestore listen error: $e");
    });

    // 3. run background sync of any offline changes
    // if we added stuff while offline, this function pushes it up to the cloud now that we are connected again!
    _syncUnsyncedToFirestore();
  }

  Future<void> _syncUnsyncedToFirestore() async {
    final firestore = _firestore;
    if (firestore == null) return;

    try {
      final unsynced = await _sqliteRepo._db.getUnsyncedPeople();
      for (final row in unsynced) {
        final id = row['id'] as String;
        final entryTime = DateTime.fromMillisecondsSinceEpoch(row['entry_time'] as int);
        final exitTime = row['exit_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['exit_time'] as int)
            : null;
        final currentCamera = row['current_camera'] as int;

        final logs = await _sqliteRepo._db.getLogsForPerson(id);
        final history = logs.map((l) => {
          'status': l['status'] as String,
          'timestamp': DateTime.fromMillisecondsSinceEpoch(l['timestamp'] as int).toIso8601String(),
        }).toList();

        await firestore.collection('tracked_persons').doc(id).set({
          'id': id,
          'entryTime': entryTime.toIso8601String(),
          'currentCamera': currentCamera,
          'exitTime': exitTime?.toIso8601String(),
          'history': history,
        }, SetOptions(merge: true));

        await _sqliteRepo._db.markSynced(id);
      }
    } catch (e) {
      debugPrint("Error syncing unsynced data to Firestore: $e");
    }
  }

  @override
  void addPerson(TrackedPerson person) {
    // 1. write to local sqlite instantly so the ui updates without any lag
    _sqliteRepo.addPerson(person);

    // 2. queue the write to firestore cloud
    // the cool part: if there is no internet, firestore naturally holds onto this and sends it automatically when internet returns!
    _firestore?.collection('tracked_persons').doc(person.id).set({
      'id': person.id,
      'entryTime': person.entryTime.toIso8601String(),
      'currentCamera': person.currentCamera,
      'history': person.history.map((log) => {
        'status': log.status,
        'timestamp': log.timestamp.toIso8601String(),
      }).toList(),
    }).then((_) {
      _sqliteRepo._db.markSynced(person.id);
    }).catchError((e) {
      // Catch error to prevent crashing, Firestore will retry automatically
      debugPrint("Firestore addPerson error: $e");
    });
  }

  @override
  void updatePerson(TrackedPerson person) {
    // 1. Update local SQLite instantly
    _sqliteRepo.updatePerson(person);

    // 2. Queue update to Firestore (works offline natively)
    _firestore?.collection('tracked_persons').doc(person.id).update({
      'currentCamera': person.currentCamera,
      'exitTime': person.exitTime?.toIso8601String(),
      'history': FieldValue.arrayUnion([
        if (person.history.isNotEmpty)
          {
            'status': person.history.last.status,
            'timestamp': person.history.last.timestamp.toIso8601String(),
          }
      ]),
    }).then((_) {
      _sqliteRepo._db.markSynced(person.id);
    }).catchError((e) {
      // If document doesn't exist yet (queued), we can use set with merge
      _firestore?.collection('tracked_persons').doc(person.id).set({
        'id': person.id,
        'entryTime': person.entryTime.toIso8601String(),
        'currentCamera': person.currentCamera,
        'exitTime': person.exitTime?.toIso8601String(),
        'history': person.history.map((log) => {
          'status': log.status,
          'timestamp': log.timestamp.toIso8601String(),
        }).toList(),
      }, SetOptions(merge: true)).then((_) {
        _sqliteRepo._db.markSynced(person.id);
      }).catchError((err) {
        debugPrint("Firestore updatePerson fallback error: $err");
      });
    });
  }
}

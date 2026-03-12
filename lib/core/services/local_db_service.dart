// lib/core/services/local_db_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final rootPath = await getDatabasesPath();
    final dbPath = join(rootPath, 'app_local.db');

    return await openDatabase(
      dbPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS employees');
          await db.execute('DROP TABLE IF EXISTS attendance');
          await _onCreate(db, newVersion);
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create employees table
    await db.execute('''
      CREATE TABLE employees (
        id TEXT PRIMARY KEY,
        name TEXT,
        email TEXT,
        phone TEXT,
        department TEXT,
        position TEXT,
        address TEXT,
        photoUrl TEXT,
        faceDescriptor TEXT,
        joinDate TEXT,
        createdAt TEXT,
        createdBy TEXT,
        createdByRole TEXT,
        createdByName TEXT,
        isActive INTEGER,
        employeeCode TEXT
      )
    ''');

    // Create attendance table
    await db.execute('''
      CREATE TABLE attendance (
        id TEXT PRIMARY KEY,
        employeeId TEXT,
        employeeName TEXT,
        employeePhotoUrl TEXT,
        department TEXT,
        date TEXT,
        loginTime TEXT,
        logoutTime TEXT,
        status TEXT,
        workHours REAL,
        isSynced INTEGER DEFAULT 0,
        localPhotoPath TEXT
      )
    ''');
  }

  // --- Employee Methods ---

  Future<void> saveEmployee(Map<String, dynamic> employeeMap) async {
    final db = await database;
    await db.insert('employees', employeeMap, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveEmployees(List<Map<String, dynamic>> employees) async {
    final db = await database;
    Batch batch = db.batch();
    for (var emp in employees) {
      batch.insert('employees', emp, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getEmployees() async {
    final db = await database;
    return await db.query('employees');
  }

  Future<Map<String, dynamic>?> getEmployee(String id) async {
    final db = await database;
    final results = await db.query('employees', where: 'id = ?', whereArgs: [id]);
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }
  
  Future<void> clearEmployees() async {
    final db = await database;
    await db.delete('employees');
  }

  // --- Attendance Methods ---
  
  Future<void> saveAttendance(Map<String, dynamic> attendanceMap) async {
    final db = await database;
    await db.insert('attendance', attendanceMap, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedAttendance() async {
    final db = await database;
    return await db.query('attendance', where: 'isSynced = ?', whereArgs: [0]);
  }
  
  Future<List<Map<String, dynamic>>> getAttendanceForEmployee(String employeeId) async {
    final db = await database;
    return await db.query('attendance', where: 'employeeId = ?', whereArgs: [employeeId], orderBy: 'date DESC');
  }
  
  Future<Map<String, dynamic>?> getTodayAttendance(String id) async {
    final db = await database;
    final results = await db.query('attendance', where: 'id = ?', whereArgs: [id]);
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  Future<void> markAttendanceSynced(String id) async {
    final db = await database;
    await db.update('attendance', {'isSynced': 1}, where: 'id = ?', whereArgs: [id]);
  }
}

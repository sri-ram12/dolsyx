import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class KeyStore {
  static final KeyStore _instance = KeyStore._internal();
  factory KeyStore() => _instance;
  KeyStore._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'dolsyx_e2ee.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE identity_keys (
            id TEXT PRIMARY KEY,
            userId TEXT,
            publicKey TEXT,
            privateKey TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE signed_prekeys (
            id INTEGER PRIMARY KEY,
            deviceId INTEGER,
            publicKey TEXT,
            privateKey TEXT,
            signature TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE onetime_prekeys (
            id INTEGER PRIMARY KEY,
            publicKey TEXT,
            privateKey TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            sessionKey TEXT
          )
        ''');
      },
    );
  }

  Future<void> saveIdentityKeyPair(String userId, Map<String, dynamic> keyPair) async {
    final database = await db;
    await database.insert(
      'identity_keys',
      {
        'id': 'main',
        'userId': userId,
        'publicKey': keyPair['publicKey'],
        'privateKey': keyPair['privateKey']
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getIdentityKeyPair(String userId) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'identity_keys',
      where: 'id = ?',
      whereArgs: ['main'],
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<void> saveSignedPreKey(int deviceId, int keyId, Map<String, dynamic> keyPair, String signature) async {
    final database = await db;
    await database.insert(
      'signed_prekeys',
      {
        'id': keyId,
        'deviceId': deviceId,
        'publicKey': keyPair['publicKey'],
        'privateKey': keyPair['privateKey'],
        'signature': signature
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getSignedPreKey(int keyId) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'signed_prekeys',
      where: 'id = ?',
      whereArgs: [keyId],
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<void> saveOneTimePreKeys(List<Map<String, dynamic>> keys) async {
    final database = await db;
    Batch batch = database.batch();
    for (var key in keys) {
      batch.insert(
        'onetime_prekeys',
        {
          'id': key['keyId'],
          'publicKey': key['publicKey'],
          'privateKey': key['privateKey'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>?> getOneTimePreKey(int keyId) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'onetime_prekeys',
      where: 'id = ?',
      whereArgs: [keyId],
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<void> deleteOneTimePreKey(int keyId) async {
    final database = await db;
    await database.delete(
      'onetime_prekeys',
      where: 'id = ?',
      whereArgs: [keyId],
    );
  }

  Future<int> getOneTimePreKeyCount() async {
    final database = await db;
    final count = Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM onetime_prekeys'));
    return count ?? 0;
  }

  Future<void> saveSession(String remoteUserId, Map<String, dynamic> sessionData) async {
    final database = await db;
    await database.insert(
      'sessions',
      {
        'id': remoteUserId,
        'sessionKey': sessionData['sessionKey'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getSession(String remoteUserId) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [remoteUserId],
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }
}

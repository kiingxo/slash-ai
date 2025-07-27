import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class CodeChunk {
  final String id;
  final String fileName;
  final String chunkText;
  final List<double> embedding;

  CodeChunk({
    required this.id,
    required this.fileName,
    required this.chunkText,
    required this.embedding,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_name': fileName,
      'chunk_text': chunkText,
      'embedding': embedding.join(','), // Store embedding as a comma-separated string
    };
  }

  static CodeChunk fromMap(Map<String, dynamic> map) {
    return CodeChunk(
      id: map['id'],
      fileName: map['file_name'],
      chunkText: map['chunk_text'],
      embedding: (map['embedding'] as String)
          .split(',')
          .map((e) => double.parse(e))
          .toList(),
    );
  }
}

class CodeDatabase {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'code_chunks.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE chunks('
          'id TEXT PRIMARY KEY,'
          'file_name TEXT,'
          'chunk_text TEXT,'
          'embedding TEXT)', // Store embedding as TEXT
        );
      },
    );
  }

  Future<void> insertChunk(CodeChunk chunk) async {
    final db = await database;
    await db.insert('chunks', chunk.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<CodeChunk>> getAllChunks() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('chunks');
    return List.generate(maps.length, (i) {
      return CodeChunk.fromMap(maps[i]);
    });
  }

  Future<void> deleteAllChunks() async {
    final db = await database;
    await db.delete('chunks');
  }
}
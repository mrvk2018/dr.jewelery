class ScrapBalanceRow {
  const ScrapBalanceRow({
    required this.branch,
    required this.purity,
    required this.totalWeightG,
    required this.totalIntakeG,
    required this.totalWriteoffG,
    required this.operationCount,
  });

  final String branch;
  final String purity;
  final double totalWeightG;
  final double totalIntakeG;
  final double totalWriteoffG;
  final int operationCount;

  static List<ScrapBalanceRow> listFromRows(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((row) {
      final map = Map<String, dynamic>.from(row);
      return ScrapBalanceRow(
        branch: map['branch']?.toString() ?? '',
        purity: map['purity']?.toString() ?? '',
        totalWeightG: numToDouble(map['total_weight_g']),
        totalIntakeG: numToDouble(map['total_intake_g']),
        totalWriteoffG: numToDouble(map['total_writeoff_g']),
        operationCount: _int(map['operation_count']),
      );
    }).toList(growable: false);
  }

  static List<ScrapBranchTotal> branchTotalsFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((row) {
      final map = Map<String, dynamic>.from(row);
      return ScrapBranchTotal(
        branch: map['branch']?.toString() ?? '',
        totalWeightG: numToDouble(map['total_weight_g']),
        totalIntakeG: numToDouble(map['total_intake_g']),
        totalWriteoffG: numToDouble(map['total_writeoff_g']),
        operationCount: _int(map['operation_count']),
      );
    }).toList(growable: false);
  }

  static ScrapGrandTotal? grandFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return ScrapGrandTotal(
      totalWeightG: numToDouble(map['total_weight_g']),
      totalIntakeG: numToDouble(map['total_intake_g']),
      totalWriteoffG: numToDouble(map['total_writeoff_g']),
      operationCount: _int(map['operation_count']),
    );
  }

  static double numToDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int _int(Object? v) {
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class ScrapBranchTotal {
  const ScrapBranchTotal({
    required this.branch,
    required this.totalWeightG,
    required this.totalIntakeG,
    required this.totalWriteoffG,
    required this.operationCount,
  });

  final String branch;
  final double totalWeightG;
  final double totalIntakeG;
  final double totalWriteoffG;
  final int operationCount;
}

class ScrapGrandTotal {
  const ScrapGrandTotal({
    required this.totalWeightG,
    required this.totalIntakeG,
    required this.totalWriteoffG,
    required this.operationCount,
  });

  final double totalWeightG;
  final double totalIntakeG;
  final double totalWriteoffG;
  final int operationCount;
}

class ScrapLedgerEntry {
  const ScrapLedgerEntry({
    required this.id,
    required this.branch,
    required this.purity,
    required this.movementType,
    required this.weightDeltaG,
    this.sourceId,
    this.sourceTable,
    this.recipientOrReason,
    this.comment,
    this.sellerCode,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String branch;
  final String purity;
  final String movementType;
  final double weightDeltaG;
  final String? sourceId;
  final String? sourceTable;
  final String? recipientOrReason;
  final String? comment;
  final String? sellerCode;
  final String? createdBy;
  final DateTime? createdAt;

  static List<ScrapLedgerEntry> listFromRpc(Map<String, dynamic> raw) {
    final rows = raw['rows'];
    if (rows is! List) return const [];
    return rows.whereType<Map>().map(ScrapLedgerEntry.fromMap).toList(growable: false);
  }

  factory ScrapLedgerEntry.fromMap(Map map) {
    final row = Map<String, dynamic>.from(map);
    return ScrapLedgerEntry(
      id: row['id']?.toString() ?? '',
      branch: row['branch']?.toString() ?? '',
      purity: row['purity']?.toString() ?? '',
      movementType: row['movement_type']?.toString() ?? '',
      weightDeltaG: ScrapBalanceRow.numToDouble(row['weight_delta_g']),
      sourceId: _text(row['source_id']),
      sourceTable: _text(row['source_table']),
      recipientOrReason: _text(row['recipient_or_reason']),
      comment: _text(row['comment']),
      sellerCode: _text(row['seller_code']),
      createdBy: _text(row['created_by']),
      createdAt: _time(row['created_at']),
    );
  }

  static String? _text(Object? v) {
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? null : t;
  }

  static DateTime? _time(Object? v) {
    final text = v?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }
}
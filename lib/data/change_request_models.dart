/// App 內「功能許願」（0069，老闆 2026-10-27）：老闆／店長寫需求 → Claude 改程式 → 看預覽 → 老闆核准上線
/// 畫面上一律稱「後臺」（老闆 2026-10-27）：資料庫或 GitHub 回報的文字裡若寫 Claude，顯示時換掉
String backstageText(String s) => s.replaceAll('Claude', '後臺');

enum ChangeStatus { queued, running, ready, failed, review, approved, merged, cancelled }

ChangeStatus changeStatusFrom(String s) =>
    ChangeStatus.values.firstWhere((x) => x.name == s, orElse: () => ChangeStatus.queued);

String changeStatusLabel(ChangeStatus s) => switch (s) {
      ChangeStatus.queued => '排隊中',
      ChangeStatus.running => '後臺修改中',
      ChangeStatus.ready => '修改好了，請看預覽',
      ChangeStatus.failed => '沒有成功',
      ChangeStatus.review => '等老闆核准',
      ChangeStatus.approved => '上線中',
      ChangeStatus.merged => '已上線',
      ChangeStatus.cancelled => '已取消',
    };

class ChangeRequest {
  final String id;
  final String storeId;
  final String title;
  final String requestedBy;
  final String requesterName;
  final ChangeStatus status;
  final String? previewUrl;
  final int? prNumber;
  final String? lastError;
  final int runCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? runStartedAt;
  ChangeRequest({
    required this.id,
    required this.storeId,
    required this.title,
    required this.requestedBy,
    required this.requesterName,
    required this.status,
    this.previewUrl,
    this.prNumber,
    this.lastError,
    this.runCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.runStartedAt,
  });

  /// 還在進行（排隊、修改中、上線中）：畫面會自動更新
  bool get busy => status == ChangeStatus.queued || status == ChangeStatus.running || status == ChangeStatus.approved;
  bool get finished => status == ChangeStatus.merged || status == ChangeStatus.cancelled;
  bool get hasPreview => previewUrl != null;

  factory ChangeRequest.fromRow(Map<String, dynamic> r) => ChangeRequest(
        id: r['id'] as String,
        storeId: r['store_id'] as String,
        title: r['title'] as String,
        requestedBy: r['requested_by'] as String,
        requesterName: r['requester_name'] as String? ?? '',
        status: changeStatusFrom(r['status'] as String),
        previewUrl: r['preview_url'] as String?,
        prNumber: (r['pr_number'] as num?)?.toInt(),
        lastError: r['last_error'] == null ? null : backstageText(r['last_error'] as String),
        runCount: (r['run_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(r['updated_at'] as String).toLocal(),
        runStartedAt: r['run_started_at'] == null ? null : DateTime.parse(r['run_started_at'] as String).toLocal(),
      );

  ChangeRequest copyWith({ChangeStatus? status, String? previewUrl, int? prNumber, String? lastError, int? runCount}) =>
      ChangeRequest(
        id: id,
        storeId: storeId,
        title: title,
        requestedBy: requestedBy,
        requesterName: requesterName,
        status: status ?? this.status,
        previewUrl: previewUrl ?? this.previewUrl,
        prNumber: prNumber ?? this.prNumber,
        lastError: lastError ?? this.lastError,
        runCount: runCount ?? this.runCount,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        runStartedAt: runStartedAt,
      );
}

/// 對話：需求、再改一次、Claude 的說明、系統（送審、退回、上線…）
class ChangeMessage {
  final int id;
  final String kind; // request／followup／claude／system
  final String authorName;
  final String body;
  final DateTime createdAt;
  /// 附的照片代號（0071）
  final List<String> photoIds;
  ChangeMessage({required this.id, required this.kind, required this.authorName, required this.body, required this.createdAt, this.photoIds = const []});
  factory ChangeMessage.fromRow(Map<String, dynamic> r, {List<String> photoIds = const []}) => ChangeMessage(
        id: (r['id'] as num).toInt(),
        kind: r['kind'] as String,
        authorName: backstageText(r['author_name'] as String? ?? ''),
        body: backstageText(r['body'] as String),
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        photoIds: photoIds,
      );
}

/// 本月已用次數與上限（老闆 limit 為 null＝不限）
class ChangeQuota {
  final int used;
  final int? limit;
  const ChangeQuota(this.used, this.limit);
  bool get exhausted => limit != null && used >= limit!;
}

class ReviewData {
  final String title;
  final String? summary;
  final List<String> changedFiles;
  final String? diff; // optional unified diff bundle for display

  const ReviewData({
    required this.title,
    this.summary,
    this.changedFiles = const [],
    this.diff,
  });

  ReviewData copyWith({
    String? title,
    String? summary,
    List<String>? changedFiles,
    String? diff,
  }) {
    return ReviewData(
      title: title ?? this.title,
      summary: summary ?? this.summary,
      changedFiles: changedFiles ?? this.changedFiles,
      diff: diff ?? this.diff,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'changedFiles': changedFiles,
        'diff': diff,
      };

  factory ReviewData.fromJson(Map<String, dynamic> json) => ReviewData(
        title: (json['title'] as String?) ?? '',
        summary: json['summary'] as String?,
        changedFiles: (json['changedFiles'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        diff: json['diff'] as String?,
      );
}

// ReviewData model for code review and edit suggestions
class ReviewData {
  final String fileName;
  final String oldContent;
  final String newContent;
  final String summary;
  ReviewData({
    required this.fileName,
    required this.oldContent,
    required this.newContent,
    required this.summary,
  });
} 
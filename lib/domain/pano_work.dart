class PanoWork {
  const PanoWork({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.imagePath,
    required this.thumbPath,
    required this.source,
    this.width = 2048,
    this.height = 1024,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final String imagePath;
  final String thumbPath;
  final String source;
  final int width;
  final int height;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'imagePath': imagePath,
        'thumbPath': thumbPath,
        'source': source,
        'width': width,
        'height': height,
      };

  factory PanoWork.fromJson(Map<String, dynamic> json) => PanoWork(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        imagePath: json['imagePath'] as String,
        thumbPath: json['thumbPath'] as String,
        source: json['source'] as String? ?? 'capture',
        width: json['width'] as int? ?? 2048,
        height: json['height'] as int? ?? 1024,
      );
}

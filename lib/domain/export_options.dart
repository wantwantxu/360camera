enum ExportType { equirectangular, snapshot }

enum ExportResolution { res2k, res4k }

enum ExportFormat { jpeg, png }

class ExportOptions {
  const ExportOptions({
    this.type = ExportType.equirectangular,
    this.resolution = ExportResolution.res2k,
    this.format = ExportFormat.jpeg,
    this.includeWatermark = true,
  });

  final ExportType type;
  final ExportResolution resolution;
  final ExportFormat format;
  final bool includeWatermark;

  ExportOptions copyWith({
    ExportType? type,
    ExportResolution? resolution,
    ExportFormat? format,
    bool? includeWatermark,
  }) {
    return ExportOptions(
      type: type ?? this.type,
      resolution: resolution ?? this.resolution,
      format: format ?? this.format,
      includeWatermark: includeWatermark ?? this.includeWatermark,
    );
  }

  (int, int) get pixelSize => switch (resolution) {
        ExportResolution.res2k => (2048, 1024),
        ExportResolution.res4k => (4096, 2048),
      };
}

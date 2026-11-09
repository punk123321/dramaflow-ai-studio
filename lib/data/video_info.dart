/// What the Android picker returns for one imported video.
/// The video file itself is never copied or changed.
class VideoInfo {
  const VideoInfo({
    required this.uri,
    required this.name,
    required this.sizeBytes,
    required this.durationMs,
    required this.width,
    required this.height,
    this.thumbnailPath,
  });

  final String uri;
  final String name;
  final int sizeBytes;
  final int durationMs;
  final int width;
  final int height;
  final String? thumbnailPath;

  factory VideoInfo.fromMap(Map<Object?, Object?> m) => VideoInfo(
        uri: m['uri'] as String,
        name: (m['name'] as String?) ?? 'video',
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
        thumbnailPath: m['thumbnailPath'] as String?,
      );
}

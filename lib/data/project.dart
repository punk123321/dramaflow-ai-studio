import '../core/stage.dart';
import 'video_info.dart';

/// One drama-recap project. Workflow progress is a bitmask: bit n = Stage n done.
class Project {
  const Project({
    this.id,
    required this.name,
    required this.dramaTitle,
    required this.episode,
    this.doneMask = 0,
    this.status = 'idle',
    this.sourceVideoUri,
    this.dramaId,
    this.videoName,
    this.videoSize,
    this.videoDurationMs,
    this.videoWidth,
    this.videoHeight,
    this.videoThumb,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String dramaTitle;
  final int episode;
  final int doneMask;

  /// idle | processing | failed
  final String status;

  /// Content URI of the original video. The app never edits or deletes it.
  final String? sourceVideoUri;
  final int? dramaId;
  final String? videoName;
  final int? videoSize;
  final int? videoDurationMs;
  final int? videoWidth;
  final int? videoHeight;
  final String? videoThumb;
  final int createdAt;
  final int updatedAt;

  bool get hasVideo => sourceVideoUri != null && (videoDurationMs ?? 0) > 0;

  bool isDone(Stage s) => doneMask & (1 << s.index) != 0;

  int get doneCount {
    var n = 0;
    for (final s in Stage.values) {
      if (isDone(s)) n++;
    }
    return n;
  }

  bool get finished => doneCount == Stage.values.length;

  /// First stage not yet done, or the last stage when everything is done.
  Stage get currentStage {
    for (final s in Stage.values) {
      if (!isDone(s)) return s;
    }
    return Stage.values.last;
  }

  Project copyWith({
    int? id,
    String? name,
    String? dramaTitle,
    int? episode,
    int? doneMask,
    String? status,
    int? updatedAt,
    int? dramaId,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      dramaTitle: dramaTitle ?? this.dramaTitle,
      episode: episode ?? this.episode,
      doneMask: doneMask ?? this.doneMask,
      status: status ?? this.status,
      sourceVideoUri: sourceVideoUri,
      dramaId: dramaId ?? this.dramaId,
      videoName: videoName,
      videoSize: videoSize,
      videoDurationMs: videoDurationMs,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      videoThumb: videoThumb,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Project withStage(Stage s, bool done, int now) {
    final bit = 1 << s.index;
    final mask = done ? (doneMask | bit) : (doneMask & ~bit);
    return copyWith(doneMask: mask, updatedAt: now);
  }

  /// Attaches a newly picked video. The old index no longer fits, so the
  /// Video index stage is marked not done.
  Project withVideo(VideoInfo v, int now) {
    return Project(
      id: id,
      name: name,
      dramaTitle: dramaTitle,
      episode: episode,
      doneMask: doneMask & ~(1 << Stage.videoIndex.index),
      status: status,
      sourceVideoUri: v.uri,
      dramaId: dramaId,
      videoName: v.name,
      videoSize: v.sizeBytes,
      videoDurationMs: v.durationMs,
      videoWidth: v.width,
      videoHeight: v.height,
      videoThumb: v.thumbnailPath,
      createdAt: createdAt,
      updatedAt: now,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'drama_title': dramaTitle,
        'episode': episode,
        'done_mask': doneMask,
        'status': status,
        'source_video_uri': sourceVideoUri,
        'drama_id': dramaId,
        'video_name': videoName,
        'video_size': videoSize,
        'video_duration_ms': videoDurationMs,
        'video_width': videoWidth,
        'video_height': videoHeight,
        'video_thumb': videoThumb,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Project.fromMap(Map<String, Object?> m) => Project(
        id: m['id'] as int?,
        name: m['name'] as String,
        dramaTitle: m['drama_title'] as String,
        episode: m['episode'] as int,
        doneMask: m['done_mask'] as int,
        status: m['status'] as String,
        sourceVideoUri: m['source_video_uri'] as String?,
        dramaId: m['drama_id'] as int?,
        videoName: m['video_name'] as String?,
        videoSize: m['video_size'] as int?,
        videoDurationMs: m['video_duration_ms'] as int?,
        videoWidth: m['video_width'] as int?,
        videoHeight: m['video_height'] as int?,
        videoThumb: m['video_thumb'] as String?,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );
}

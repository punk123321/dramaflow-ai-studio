class Drama {
  const Drama({
    this.id,
    this.titleZh = '',
    this.titleMy = '',
    this.description = '',
    this.season = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String titleZh;
  final String titleMy;
  final String description;
  final int season;
  final int createdAt;
  final int updatedAt;

  /// Burmese title first, Chinese title when there is no Burmese one.
  String get displayTitle => titleMy.isNotEmpty ? titleMy : titleZh;

  Drama copyWith({
    int? id,
    String? titleZh,
    String? titleMy,
    String? description,
    int? season,
    int? updatedAt,
  }) =>
      Drama(
        id: id ?? this.id,
        titleZh: titleZh ?? this.titleZh,
        titleMy: titleMy ?? this.titleMy,
        description: description ?? this.description,
        season: season ?? this.season,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title_zh': titleZh,
        'title_my': titleMy,
        'description': description,
        'season': season,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Drama.fromMap(Map<String, Object?> m) => Drama(
        id: m['id'] as int?,
        titleZh: m['title_zh'] as String,
        titleMy: m['title_my'] as String,
        description: m['description'] as String,
        season: m['season'] as int,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );
}

class Episode {
  const Episode({
    this.id,
    required this.dramaId,
    required this.number,
    this.durationMin = 0,
    this.source = '',
    this.completed = false,
  });

  final int? id;
  final int dramaId;
  final int number;
  final int durationMin;
  final String source;
  final bool completed;

  Episode copyWith({int? id, int? number, int? durationMin, String? source, bool? completed}) =>
      Episode(
        id: id ?? this.id,
        dramaId: dramaId,
        number: number ?? this.number,
        durationMin: durationMin ?? this.durationMin,
        source: source ?? this.source,
        completed: completed ?? this.completed,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'drama_id': dramaId,
        'number': number,
        'duration_min': durationMin,
        'source': source,
        'completed': completed ? 1 : 0,
      };

  factory Episode.fromMap(Map<String, Object?> m) => Episode(
        id: m['id'] as int?,
        dramaId: m['drama_id'] as int,
        number: m['number'] as int,
        durationMin: m['duration_min'] as int,
        source: m['source'] as String,
        completed: (m['completed'] as int) == 1,
      );
}

enum DramaStatus { none, ongoing, done }

/// Status comes from the episodes: none, some unfinished, or all finished.
DramaStatus dramaStatus(List<Episode> episodes) {
  if (episodes.isEmpty) return DramaStatus.none;
  return episodes.every((e) => e.completed) ? DramaStatus.done : DramaStatus.ongoing;
}

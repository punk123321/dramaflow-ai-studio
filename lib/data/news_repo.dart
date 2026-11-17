import '../core/news.dart';
import 'handoff_repo.dart';

/// Feeds and the last loaded stories, kept in the local database as app-wide
/// documents (not tied to a project, not part of a backup).
class NewsRepo {
  static const _projectId = -2;
  static const _feedsKind = 'news_feeds';
  static const _cacheKind = 'news_cache';
  final _docs = HandoffRepo();

  /// Saved feeds, or the suggestions when none were saved yet.
  Future<List<NewsFeed>> feeds() async => decodeFeeds(await _docs.getDoc(_projectId, _feedsKind)) ?? suggestedFeeds;

  Future<void> saveFeeds(List<NewsFeed> f) => _docs.setDoc(_projectId, _feedsKind, encodeFeeds(f));

  Future<({List<NewsItem> items, int savedMs})> cached() async => decodeItems(await _docs.getDoc(_projectId, _cacheKind));

  Future<void> saveCache(List<NewsItem> items, int nowMs) => _docs.setDoc(_projectId, _cacheKind, encodeItems(items, nowMs));
}

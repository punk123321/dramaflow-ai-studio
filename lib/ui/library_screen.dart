import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/drama.dart';
import '../state/library_store.dart';
import 'drama_detail_screen.dart';
import 'drama_sheet.dart';
import 'widgets.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  static const _filters = <LibraryFilter, String>{
    LibraryFilter.all: 'အားလုံး',
    LibraryFilter.ongoing: 'ဆက်လုပ်နေ',
    LibraryFilter.done: 'ပြီးပြီ',
    LibraryFilter.none: 'အပိုင်းမရှိ',
  };

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final list = store.filtered;

    return DfScaffold(
      appBar: AppBar(title: const Text('Drama Library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDramaSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('ဇာတ်လမ်းအသစ်'),
      ),
      body: store.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    onChanged: store.setQuery,
                    decoration: const InputDecoration(
                      hintText: 'ဇာတ်လမ်း ရှာမယ်',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final e in _filters.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(e.value),
                            selected: store.filter == e.key,
                            onSelected: (_) => store.setFilter(e.key),
                          ),
                        ),
                    ],
                  ),
                ),
                if (store.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: ErrorBanner(store.error!),
                  ),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              store.dramas.isEmpty
                                  ? 'ဇာတ်လမ်း မရှိသေးပါဘူး။ “ဇာတ်လမ်းအသစ်” ကို နှိပ်ပြီး ထည့်ပါ။'
                                  : 'ကိုက်ညီတဲ့ ဇာတ်လမ်း မတွေ့ပါဘူး။',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: DfColors.muted),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _DramaCard(drama: list[i]),
                        ),
                ),
              ],
            ),
    );
  }
}

class _DramaCard extends StatelessWidget {
  const _DramaCard({required this.drama});

  final Drama drama;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final eps = store.episodesOf(drama.id!);
    final done = eps.where((e) => e.completed).length;
    final status = dramaStatus(eps);
    final (label, color) = switch (status) {
      DramaStatus.none => ('အပိုင်းမရှိ', DfColors.muted),
      DramaStatus.ongoing => ('ဆက်လုပ်နေ', DfColors.warn),
      DramaStatus.done => ('ပြီးပြီ', DfColors.ok),
    };
    final showZh = drama.titleMy.isNotEmpty && drama.titleZh.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: DfColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DfColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => DramaDetailScreen(dramaId: drama.id!)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Poster(title: drama.displayTitle, width: 44, height: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      drama.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (showZh)
                      Text(drama.titleZh, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: DfColors.muted, fontSize: 13)),
                    Text(
                      'Season ${drama.season} · ပြီး $done / ${eps.length} ပိုင်း',
                      style: const TextStyle(color: DfColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: color.withValues(alpha: 0.55)),
                ),
                child: Text(label, style: TextStyle(color: color, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

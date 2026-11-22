import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/core/backend_kind.dart';

void main() {
  test('the two backends are told apart by their /health service name', () {
    expect(backendKindOf('DramaFlow Recap Backend'), BackendKind.recap);
    expect(backendKindOf('AI News Studio Backend v2'), BackendKind.news);
    expect(backendKindOf(''), BackendKind.unknown);
    expect(backendKindOf(null), BackendKind.unknown);
    expect(backendKindOf('Something else'), BackendKind.unknown);
  });

  test('the wrong-backend texts say which notebook to run', () {
    expect(wrongBackendForRecap, contains('recap_colab'));
    expect(wrongBackendForNews, contains('news_backend'));
  });
}

/// Which of the two backends answers at an address, from the "service" name
/// in its /health reply. The app has two: the News Video backend and the Recap
/// backend, and mixing their addresses up gives a confusing "Not Found".
enum BackendKind { recap, news, unknown }

BackendKind backendKindOf(String? service) {
  final s = (service ?? '').toLowerCase();
  if (s.contains('recap')) return BackendKind.recap;
  if (s.contains('news')) return BackendKind.news;
  return BackendKind.unknown;
}

const wrongBackendForRecap =
    'ဒီ URL က News Video backend ပါ၊ Recap backend မဟုတ်ဘူး။ Recap အတွက် "dramaflow_recap_colab_standalone" notebook ကို run ပြီး '
    'ထွက်လာတဲ့ URL#TOKEN ကို ထည့်ပါ (News Video ရဲ့ URL ကို News Video စာမျက်နှာမှာပဲ ထားပါ)';

const wrongBackendForNews =
    'ဒီ URL က Recap backend ပါ၊ News Video backend မဟုတ်ဘူး။ News Video အတွက် "dramaflow_news_backend" notebook ကို run ပြီး '
    'ထွက်လာတဲ့ URL#TOKEN ကို ဒီစာမျက်နှာမှာ ထည့်ပါ';

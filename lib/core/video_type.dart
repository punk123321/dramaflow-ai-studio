/// The video types Gemini accepts, found from the first bytes of the file
/// (the app copies the picked video under a fixed name, so the name says nothing).
class VideoKind {
  const VideoKind(this.mime, {this.supported = true});

  final String mime;
  final bool supported;
}

/// [head] is the first 16 or more bytes of the file. Unknown content is treated
/// as MP4 (most phone videos are) so a rare container is tried instead of refused.
VideoKind sniffVideoKind(List<int> head) {
  bool at(int i, String s) {
    if (head.length < i + s.length) return false;
    for (var k = 0; k < s.length; k++) {
      if (head[i + k] != s.codeUnitAt(k)) return false;
    }
    return true;
  }

  if (at(4, 'ftyp')) {
    if (at(8, 'qt')) return const VideoKind('video/quicktime');
    if (at(8, '3g')) return const VideoKind('video/3gpp');
    return const VideoKind('video/mp4');
  }
  if (head.length >= 4 && head[0] == 0x1A && head[1] == 0x45 && head[2] == 0xDF && head[3] == 0xA3) {
    // WebM and MKV share this header; Gemini takes WebM only. A full check needs the
    // doctype, so let the upload try and explain a refusal.
    return const VideoKind('video/webm');
  }
  if (at(0, 'RIFF') && at(8, 'AVI ')) return const VideoKind('video/avi');
  if (at(0, 'FLV')) return const VideoKind('video/x-flv');
  if (head.length >= 4 && head[0] == 0x30 && head[1] == 0x26 && head[2] == 0xB2 && head[3] == 0x75) return const VideoKind('video/wmv');
  if (head.length >= 4 && head[0] == 0 && head[1] == 0 && head[2] == 1 && (head[3] == 0xBA || head[3] == 0xB3)) return const VideoKind('video/mpeg');
  return const VideoKind('video/mp4');
}

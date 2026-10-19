// WebRTC to our own media server, over WHIP (publish) and WHEP (watch).
//
// Both are the same three steps and need no SDK: build a peer connection,
// POST the local SDP offer to the URL the backend issued, set the answer
// that comes back. The signed token is already inside that URL, so there is
// nothing else to authenticate with and no signalling socket to keep alive —
// once the answer is set, media flows phone↔server directly and the
// connection objects below exist only to be disposed of later.
//
// Why the offer waits for ICE: the server does not accept trickled
// candidates, so they have to travel inside the offer. _gatherIce waits for
// gathering to finish but gives up quickly — a viewer whose TURN relay is
// slow to answer should start watching with the candidates we already have
// instead of watching a spinner.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../models/live_session.dart';

/// How long to let ICE gathering run before posting the offer anyway.
/// Host candidates appear in milliseconds; this budget is really for the
/// TURN relay candidate, which only viewers behind carrier NAT need.
const _iceGatherBudget = Duration(seconds: 3);

/// A live-media failure already phrased for the user. The screens show
/// [message] as-is, so everything thrown from here is in Arabic.
class LiveMediaException implements Exception {
  final String message;
  const LiveMediaException(this.message);

  @override
  String toString() => message;
}

/// Where a connection is in its life: the screens use this to choose
/// between a spinner, the picture, and an error.
enum LiveMediaState { connecting, live, reconnecting, failed }

typedef LiveMediaStateCallback = void Function(LiveMediaState state);

LiveMediaState _stateOf(RTCPeerConnectionState raw) {
  switch (raw) {
    case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
      return LiveMediaState.live;
    case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      return LiveMediaState.reconnecting;
    case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
    case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
      return LiveMediaState.failed;
    default:
      return LiveMediaState.connecting;
  }
}

Future<RTCPeerConnection> _newConnection(LiveStreamCredentials credentials) {
  return createPeerConnection({
    'iceServers': credentials.iceServers,
    // Unified plan is the only semantics WHIP/WHEP are specified against.
    'sdpSemantics': 'unified-plan',
  });
}

Future<void> _gatherIce(RTCPeerConnection pc) async {
  if (pc.iceGatheringState ==
      RTCIceGatheringState.RTCIceGatheringStateComplete) {
    return;
  }
  final gathered = Completer<void>();
  pc.onIceGatheringState = (state) {
    if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
        !gathered.isCompleted) {
      gathered.complete();
    }
  };
  await gathered.future.timeout(_iceGatherBudget, onTimeout: () {});
  pc.onIceGatheringState = null;
}

/// POSTs [pc]'s offer to [url] and applies the answer. One round trip is
/// the whole of WHIP/WHEP signalling.
Future<void> _exchangeSdp(RTCPeerConnection pc, String url) async {
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  await _gatherIce(pc);
  final local = await pc.getLocalDescription();

  final http.Response response;
  try {
    response = await http.post(
      Uri.parse(url),
      headers: const {'Content-Type': 'application/sdp'},
      body: local?.sdp ?? offer.sdp,
    );
  } catch (_) {
    // Never reached the box at all: no DNS, no route, or the phone lost
    // its connection between fetching the credentials and using them.
    throw const LiveMediaException('تعذّر الوصول إلى خادم البث — تحقّق من اتصالك');
  }

  if (response.statusCode != 200 && response.statusCode != 201) {
    throw LiveMediaException(_messageForStatus(response.statusCode));
  }

  await pc.setRemoteDescription(
    RTCSessionDescription(_answerSdpFrom(response.body), 'answer'),
  );
}

/// WHIP/WHEP answer with the raw SDP as the body; the server's older
/// non-standard endpoints wrap it in `{"code":0,"sdp":"..."}`. Accepting
/// both costs four lines and means a server-side endpoint change cannot
/// break published apps.
String _answerSdpFrom(String body) {
  final trimmed = body.trimLeft();
  if (!trimmed.startsWith('{')) return body;
  try {
    final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
    final sdp = decoded['sdp'] as String?;
    if (sdp != null && sdp.isNotEmpty) return sdp;
  } catch (_) {
    // Fall through: whatever it is, it is not an answer we can use.
  }
  throw const LiveMediaException('ردّ خادم البث غير مفهوم');
}

String _messageForStatus(int status) {
  // The token travels in the URL and expires, so 401/403/404 here is
  // almost always "your credentials went stale while you were away"
  // rather than anything the viewer did wrong.
  if (status == 401 || status == 403) {
    return 'انتهت صلاحية الإذن بالبث — أعد المحاولة';
  }
  if (status == 404) return 'البث غير موجود على الخادم';
  return 'تعذّر بدء البث (خطأ $status)';
}

/// The store owner's side: camera and microphone out to the server.
class LiveBroadcastConnection {
  final RTCPeerConnection _pc;

  /// The camera feed, for the local preview. Owned by this object.
  final MediaStream localStream;

  bool _disposed = false;

  LiveBroadcastConnection._(this._pc, this.localStream);

  static Future<LiveBroadcastConnection> publish(
    LiveStreamCredentials credentials, {
    LiveMediaStateCallback? onState,
  }) async {
    final url = credentials.whipUrl;
    if (url == null || url.isEmpty) {
      throw const LiveMediaException('لم يصل عنوان النشر من الخادم');
    }

    final stream = await _openCamera();
    final pc = await _newConnection(credentials);
    pc.onConnectionState = (state) => onState?.call(_stateOf(state));
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }

    try {
      await _exchangeSdp(pc, url);
    } catch (_) {
      // Release the camera before rethrowing: a failed attempt that keeps
      // the lens open means the retry cannot get it.
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      await pc.close();
      rethrow;
    }

    return LiveBroadcastConnection._(pc, stream);
  }

  /// The seller films merchandise, so the back camera is the useful
  /// default. 720p portrait is what every phone we support can capture and
  /// roughly what an Iraqi mobile uplink can carry; if a camera cannot
  /// meet that floor we take whatever it offers rather than refuse to go
  /// live over a resolution.
  static Future<MediaStream> _openCamera() async {
    const preferred = <String, dynamic>{
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '720',
          'minHeight': '1280',
          'minFrameRate': '24',
        },
        'facingMode': 'environment',
        'optional': <dynamic>[],
      },
    };
    try {
      return await navigator.mediaDevices.getUserMedia(preferred);
    } catch (_) {
      try {
        return await navigator.mediaDevices.getUserMedia(const {
          'audio': true,
          'video': {'facingMode': 'environment'},
        });
      } catch (_) {
        throw const LiveMediaException('تعذّر فتح الكاميرا أو الميكروفون');
      }
    }
  }

  MediaStreamTrack? get _videoTrack {
    final tracks = localStream.getVideoTracks();
    return tracks.isEmpty ? null : tracks.first;
  }

  /// Flips between the lenses without touching the connection: the track
  /// stays the same object, so the server never sees an interruption.
  Future<void> switchCamera() async {
    final track = _videoTrack;
    if (track == null) {
      throw const LiveMediaException('لا توجد كاميرا لتبديلها');
    }
    await Helper.switchCamera(track);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final track in localStream.getTracks()) {
      await track.stop();
    }
    await localStream.dispose();
    await _pc.close();
  }
}

/// A viewer's side: the broadcaster's audio and video in, nothing out.
class LiveWatchConnection {
  final RTCPeerConnection _pc;
  bool _disposed = false;

  LiveWatchConnection._(this._pc);

  /// [onStream] fires once the server's track arrives — which is a
  /// separate moment from the connection going [LiveMediaState.live], and
  /// the one the picture actually depends on.
  static Future<LiveWatchConnection> watch(
    LiveStreamCredentials credentials, {
    required void Function(MediaStream stream) onStream,
    LiveMediaStateCallback? onState,
  }) async {
    final url = credentials.whepUrl;
    if (url == null || url.isEmpty) {
      throw const LiveMediaException('لم يصل عنوان المشاهدة من الخادم');
    }

    final pc = await _newConnection(credentials);
    pc.onConnectionState = (state) => onState?.call(_stateOf(state));
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) onStream(event.streams.first);
    };

    // Receive-only on both kinds: without these the offer would carry no
    // media lines at all and the server would have nothing to answer.
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    try {
      await _exchangeSdp(pc, url);
    } catch (_) {
      await pc.close();
      rethrow;
    }

    return LiveWatchConnection._(pc);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _pc.close();
  }
}

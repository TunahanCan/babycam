class WebRtcSignalDescription {
  const WebRtcSignalDescription({required this.sdp, required this.type});

  final String sdp;
  final String type;

  factory WebRtcSignalDescription.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('WebRTC description must be an object.');
    }
    final sdp = value['sdp']?.toString().trim() ?? '';
    final type = value['type']?.toString().trim().toLowerCase() ?? '';
    if (sdp.isEmpty || (type != 'offer' && type != 'answer')) {
      throw const FormatException('Invalid WebRTC session description.');
    }
    return WebRtcSignalDescription(sdp: sdp, type: type);
  }

  Map<String, Object?> toJson() => {'sdp': sdp, 'type': type};
}

class WebRtcIceCandidateSignal {
  const WebRtcIceCandidateSignal({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  factory WebRtcIceCandidateSignal.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('ICE candidate must be an object.');
    }
    final candidate = value['candidate']?.toString().trim() ?? '';
    if (candidate.isEmpty || candidate.length > 8192) {
      throw const FormatException('Invalid ICE candidate.');
    }
    final lineIndex = value['sdpMLineIndex'];
    if (lineIndex != null && lineIndex is! int) {
      throw const FormatException('Invalid ICE media line index.');
    }
    return WebRtcIceCandidateSignal(
      candidate: candidate,
      sdpMid: value['sdpMid']?.toString(),
      sdpMLineIndex: lineIndex as int?,
    );
  }

  Map<String, Object?> toJson() => {
        'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
      };
}

class WebRtcOfferRequest {
  const WebRtcOfferRequest({
    required this.offer,
    this.video = true,
    this.audio = false,
  });

  final WebRtcSignalDescription offer;
  final bool video;
  final bool audio;

  factory WebRtcOfferRequest.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('WebRTC offer body must be an object.');
    }
    final offer = WebRtcSignalDescription.fromJson(value['offer']);
    if (offer.type != 'offer') {
      throw const FormatException('Expected an SDP offer.');
    }
    return WebRtcOfferRequest(
      offer: offer,
      video: value['video'] is bool ? value['video'] as bool : true,
      audio: value['audio'] is bool ? value['audio'] as bool : false,
    );
  }

  Map<String, Object?> toJson() => {
        'offer': offer.toJson(),
        'video': video,
        'audio': audio,
      };
}

class WebRtcOfferResponse {
  const WebRtcOfferResponse({
    required this.peerId,
    required this.answer,
    this.iceCandidates = const [],
  });

  final String peerId;
  final WebRtcSignalDescription answer;
  final List<WebRtcIceCandidateSignal> iceCandidates;

  factory WebRtcOfferResponse.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('WebRTC answer must be an object.');
    }
    final peerId = value['peerId']?.toString().trim() ?? '';
    final answer = WebRtcSignalDescription.fromJson(value['answer']);
    if (peerId.isEmpty || answer.type != 'answer') {
      throw const FormatException('Invalid WebRTC answer.');
    }
    final rawCandidates = value['iceCandidates'];
    return WebRtcOfferResponse(
      peerId: peerId,
      answer: answer,
      iceCandidates: rawCandidates is List
          ? rawCandidates.map(WebRtcIceCandidateSignal.fromJson).toList()
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
        'ok': true,
        'peerId': peerId,
        'answer': answer.toJson(),
        'iceCandidates': iceCandidates.map((item) => item.toJson()).toList(),
      };
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ConsultationRole { patient, clinic }

const String _turnUrl = String.fromEnvironment('TURN_URL');
const String _turnUsername = String.fromEnvironment('TURN_USERNAME');
const String _turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

List<Map<String, dynamic>> _iceServers() {
  final servers = <Map<String, dynamic>>[
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];
  if (_turnUrl.isNotEmpty) {
    servers.add({
      'urls': _turnUrl,
      'username': _turnUsername,
      'credential': _turnCredential,
    });
  }
  return servers;
}

class ConsultationCallScreen extends StatefulWidget {
  final String appointmentId;
  final ConsultationRole role;
  final String title;
  final String subtitle;

  const ConsultationCallScreen({
    super.key,
    required this.appointmentId,
    required this.role,
    this.title = 'Online Consultation',
    this.subtitle = '',
  });

  @override
  State<ConsultationCallScreen> createState() => _ConsultationCallScreenState();
}

class _ConsultationCallScreenState extends State<ConsultationCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingCandidates = [];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RealtimeChannel? _channel;
  Timer? _helloTimer;
  Future<void> _signalQueue = Future.value();

  bool _remoteDescriptionSet = false;
  bool _offerSent = false;
  bool _remoteJoined = false;
  bool _connected = false;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _frontCamera = true;
  bool _disposed = false;

  String _status = 'Preparing camera and microphone...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      if (_disposed) {
        await _disposeStream(stream);
        return;
      }
      _localStream = stream;
      _localRenderer.srcObject = stream;

      final pc = await createPeerConnection({
        'iceServers': _iceServers(),
        'sdpSemantics': 'unified-plan',
      });
      if (_disposed) {
        await pc.close();
        await _disposeStream(stream);
        return;
      }
      _peerConnection = pc;

      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }

      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        unawaited(_sendSignal({
          'type': 'candidate',
          'role': widget.role.name,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }));
      };

      pc.onTrack = (event) {
        if (event.streams.isNotEmpty && !_disposed) {
          _remoteRenderer.srcObject = event.streams.first;
          _setState(() => _remoteJoined = true);
        }
      };

      pc.onConnectionState = (state) {
        if (!mounted) return;
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _setState(() {
              _connected = true;
              _status = 'Connected';
            });
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            _setState(() => _status = 'Connecting...');
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            _setState(() {
              _connected = false;
              _status = 'Connection lost. Waiting to reconnect...';
            });
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _setState(() {
              _connected = false;
              _status = 'Connection failed. Please leave and try again.';
            });
          default:
            break;
        }
      };

      _subscribeToSignals();
      _setState(() => _status = 'Waiting for the other participant...');
    } catch (error) {
      if (!mounted) return;
      _setState(() {
        _error = error.toString();
        _status = 'Could not start the consultation';
      });
    }
  }

  void _subscribeToSignals() {
    final channel = Supabase.instance.client.channel(
      'consultation:${widget.appointmentId}',
      opts: const RealtimeChannelConfig(self: false),
    );
    channel.onBroadcast(event: 'webrtc', callback: _handleSignal);
    channel.subscribe((status, error) {
      if (!mounted) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        unawaited(_sendSignal({'type': 'hello', 'role': widget.role.name}));
        _helloTimer?.cancel();
        _helloTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (!_connected && !_disposed) {
            unawaited(_sendSignal({'type': 'hello', 'role': widget.role.name}));
          }
        });
      } else if (status == RealtimeSubscribeStatus.channelError) {
        _setState(() => _status = 'Waiting room unavailable: $error');
      }
    });
    _channel = channel;
  }

  void _handleSignal(Map<String, dynamic> payload) {
    _signalQueue = _signalQueue.then((_) => _processSignal(payload));
  }

  Future<void> _processSignal(Map<String, dynamic> payload) async {
    if (_disposed) return;
    final senderRole = payload['role']?.toString();
    if (senderRole == null || senderRole == widget.role.name) return;

    final type = payload['type']?.toString();
    switch (type) {
      case 'hello':
        if (!_remoteJoined) _setState(() => _remoteJoined = true);
        if (widget.role == ConsultationRole.clinic) {
          await _createOfferIfNeeded();
        }
      case 'offer':
        await _handleOffer(payload);
      case 'answer':
        await _handleAnswer(payload);
      case 'candidate':
        await _handleRemoteCandidate(payload);
      case 'bye':
        _setState(() {
          _connected = false;
          _remoteJoined = false;
          _status = 'The other participant left the consultation.';
        });
        _remoteRenderer.srcObject = null;
      default:
        break;
    }
  }

  Future<void> _createOfferIfNeeded() async {
    final pc = _peerConnection;
    if (pc == null || _offerSent || _disposed) return;
    _offerSent = true;
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _sendSignal({
        'type': 'offer',
        'role': widget.role.name,
        'sdp': offer.sdp,
        'sdpType': offer.type,
      });
    } catch (_) {
      _offerSent = false;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    final pc = _peerConnection;
    if (pc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(
        payload['sdp']?.toString(),
        payload['sdpType']?.toString(),
      ),
    );
    _remoteDescriptionSet = true;
    await _flushPendingCandidates();

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await _sendSignal({
      'type': 'answer',
      'role': widget.role.name,
      'sdp': answer.sdp,
      'sdpType': answer.type,
    });
    if (!_remoteJoined) _setState(() => _remoteJoined = true);
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final pc = _peerConnection;
    if (pc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(
        payload['sdp']?.toString(),
        payload['sdpType']?.toString(),
      ),
    );
    _remoteDescriptionSet = true;
    await _flushPendingCandidates();
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> payload) async {
    final candidate = RTCIceCandidate(
      payload['candidate']?.toString(),
      payload['sdpMid']?.toString(),
      int.tryParse(payload['sdpMLineIndex']?.toString() ?? ''),
    );
    if (!_remoteDescriptionSet) {
      _pendingCandidates.add(candidate);
      return;
    }
    await _peerConnection?.addCandidate(candidate);
  }

  Future<void> _flushPendingCandidates() async {
    for (final candidate in _pendingCandidates) {
      await _peerConnection?.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  Future<void> _sendSignal(Map<String, dynamic> payload) async {
    final channel = _channel;
    if (channel == null || _disposed) return;
    try {
      await channel.sendBroadcastMessage(event: 'webrtc', payload: payload);
    } catch (_) {}
  }

  void _setState(VoidCallback callback) {
    if (mounted) setState(callback);
  }

  Future<void> _toggleMic() async {
    final tracks = _localStream?.getAudioTracks() ?? [];
    if (tracks.isEmpty) return;
    _micEnabled = !_micEnabled;
    for (final track in tracks) {
      track.enabled = _micEnabled;
    }
    _setState(() {});
  }

  Future<void> _toggleCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    _cameraEnabled = !_cameraEnabled;
    for (final track in tracks) {
      track.enabled = _cameraEnabled;
    }
    _setState(() {});
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
    _frontCamera = !_frontCamera;
    _setState(() {});
  }

  Future<void> _endCall() async {
    await _sendSignal({'type': 'bye', 'role': widget.role.name});
    await _cleanup();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cleanup() async {
    if (_disposed) return;
    _disposed = true;
    _helloTimer?.cancel();
    _helloTimer = null;

    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }

    final pc = _peerConnection;
    _peerConnection = null;
    if (pc != null) {
      await pc.close();
      await pc.dispose();
    }

    final stream = _localStream;
    _localStream = null;
    if (stream != null) await _disposeStream(stream);

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }

  Future<void> _disposeStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRemoteVideo = _remoteRenderer.srcObject != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_endCall());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: hasRemoteVideo
                    ? RTCVideoView(
                        _remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Container(
                        color: const Color(0xFF0F172A),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircleAvatar(
                                radius: 44,
                                backgroundColor: Color(0xFF1E293B),
                                child: Icon(Icons.videocam_outlined, color: Colors.white70, size: 40),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _status,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                              if (_remoteJoined) ...[
                                const SizedBox(height: 10),
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
              Positioned(
                top: 12,
                left: 16,
                right: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (widget.subtitle.isNotEmpty)
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _connected ? Colors.greenAccent : Colors.amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _connected ? 'Live' : _status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                width: 112,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: const Color(0xFF1E293B),
                    child: _cameraEnabled
                        ? RTCVideoView(
                            _localRenderer,
                            mirror: _frontCamera,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          )
                        : const Center(
                            child: Icon(Icons.videocam_off, color: Colors.white54),
                          ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CallButton(
                      icon: _micEnabled ? Icons.mic : Icons.mic_off,
                      label: _micEnabled ? 'Mute' : 'Unmute',
                      onPressed: _toggleMic,
                    ),
                    const SizedBox(width: 18),
                    _CallButton(
                      icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                      label: _cameraEnabled ? 'Camera off' : 'Camera on',
                      onPressed: _toggleCamera,
                    ),
                    const SizedBox(width: 18),
                    _CallButton(
                      icon: Icons.cameraswitch_outlined,
                      label: 'Flip',
                      onPressed: _switchCamera,
                    ),
                    const SizedBox(width: 18),
                    _CallButton(
                      icon: Icons.call_end,
                      label: 'Leave',
                      backgroundColor: Colors.red,
                      onPressed: _endCall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? backgroundColor;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white),
          style: IconButton.styleFrom(
            backgroundColor: backgroundColor ?? Colors.white24,
            padding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}

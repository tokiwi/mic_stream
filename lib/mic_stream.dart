import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

// In reference to the implementation of the official sensors plugin
// https://github.com/flutter/plugins/tree/master/packages/sensors

/// Source and type of audio recorded
enum AudioSource {
  DEFAULT,
  MIC,
  VOICE_UPLINK,
  VOICE_DOWNLINK,
  VOICE_CALL,
  CAMCORDER,
  VOICE_RECOGNITION,
  VOICE_COMMUNICATION,
  REMOTE_SUBMIX,
  UNPROCESSED,
  VOICE_PERFORMANCE
}

/// Mono: Records using one microphone;
/// Stereo: Records using two spatially distant microphones (if applicable)
enum ChannelConfig {
  CHANNEL_IN_MONO,
  CHANNEL_IN_STEREO,
}

/// Bit depth.
/// 8-bit means each sample consists of 1 byte
/// 16-bit means each sample consists of 2 consecutive bytes, in little endian
enum AudioFormat {
  ENCODING_PCM_8BIT,
  ENCODING_PCM_16BIT,
  ENCODING_PCM_FLOAT,
  ENCODING_PCM_24BIT_PACKED,
  ENCODING_PCM_32BIT
}

class MicStream {
  static bool _requestPermission = true;

  static const AudioSource DEFAULT_AUDIO_SOURCE = AudioSource.DEFAULT;
  static const ChannelConfig DEFAULT_CHANNELS_CONFIG =
      ChannelConfig.CHANNEL_IN_MONO;
  static const AudioFormat DEFAULT_AUDIO_FORMAT = AudioFormat.ENCODING_PCM_8BIT;
  static const int DEFAULT_SAMPLE_RATE = 16000;

  static const int _MIN_SAMPLE_RATE = 1;
  static const int _MAX_SAMPLE_RATE = 100000;

  static const EventChannel _microphoneEventChannel =
      EventChannel('aaron.code.com/mic_stream');
  static const MethodChannel _microphoneMethodChannel =
      MethodChannel('aaron.code.com/mic_stream_method_channel');

  /// The actual sample rate used for streaming.  This may return zero if invoked without listening to the _microphone Stream
  static Future<int> get sampleRate => _sampleRateCompleter.future;
  static Completer<int> _sampleRateCompleter = new Completer();

  /// The actual bit depth used for streaming. This may return zero if invoked without listening to the _microphone Stream first.
  static Future<int> get bitDepth => _bitDepthCompleter.future;
  static Completer<int> _bitDepthCompleter = new Completer();

  /// The amount of recorded data, per sample, in bytes
  static Future<int> get bufferSize => _bufferSizeCompleter.future;
  static Completer<int> _bufferSizeCompleter = new Completer();

  /// The configured microphone stream and its config
  static Stream<Uint8List>? _microphone;
  static AudioSource? __audioSource;
  static int? __sampleRate;
  static ChannelConfig? __channelConfig;
  static AudioFormat? __audioFormat;

  /// This function manages the permission and ensures you're allowed to record audio
  static Future<bool> get permissionStatus async {
    if (Platform.isMacOS) {
      return true;
    }
    var micStatus = await handler.Permission.microphone.request();
    return !micStatus.isDenied && !micStatus.isPermanentlyDenied;
  }

  /// This function initializes a connection to the native backend (if not already available).
  /// Returns a Uint8List stream representing the captured audio.
  /// IMPORTANT - on iOS, there is no guarantee that captured audio will be encoded with the requested sampleRate/bitDepth.
  /// You must check the sampleRate and bitDepth properties of the MicStream object *after* invoking this method (though this does not need to be before listening to the returned stream).
  /// This is why this method returns a Uint8List - if you request a 16-bit encoding, you will need to check that
  /// the returned stream is actually returning 16-bit data, and if so, manually cast uint8List.buffer.asUint16List()
  /// audioSource:     The device used to capture audio. The default let's the OS decide.
  /// sampleRate:      The amount of samples per second. More samples give better quality at the cost of higher data transmission
  /// channelConfig:   States whether audio is mono or stereo
  /// audioFormat:     Switch between 8- and 16-bit PCM streams
  ///
  static Stream<Uint8List> microphone(
      {AudioSource? audioSource,
      int? sampleRate,
      ChannelConfig? channelConfig,
      AudioFormat? audioFormat}) {
    audioSource ??= DEFAULT_AUDIO_SOURCE;
    sampleRate ??= DEFAULT_SAMPLE_RATE;
    channelConfig ??= DEFAULT_CHANNELS_CONFIG;
    audioFormat ??= DEFAULT_AUDIO_FORMAT;

    if (sampleRate < _MIN_SAMPLE_RATE || sampleRate > _MAX_SAMPLE_RATE)
      return Stream.error(
          RangeError.range(sampleRate, _MIN_SAMPLE_RATE, _MAX_SAMPLE_RATE));

    final initStream = _requestPermission
        ? Stream.fromFuture(permissionStatus)
        : Stream.value(true);

    return initStream.asyncExpand((grantedPermission) {
      if (!grantedPermission) {
        throw Exception('Microphone permission is not granted');
      }
      return _setupMicStream(
        audioSource!,
        sampleRate!,
        channelConfig!,
        audioFormat!,
      );
    });
  }

  static Stream<Uint8List> _setupMicStream(
    AudioSource audioSource,
    int sampleRate,
    ChannelConfig channelConfig,
    AudioFormat audioFormat,
  ) {
    // If first time or configs have changed reinitialise audio recorder
    if (audioSource != __audioSource ||
        sampleRate != __sampleRate ||
        channelConfig != __channelConfig ||
        audioFormat != __audioFormat) {
      _microphone = _microphoneEventChannel.receiveBroadcastStream([
        audioSource.index,
        sampleRate,
        channelConfig == ChannelConfig.CHANNEL_IN_MONO ? 16 : 12,
        audioFormat == AudioFormat.ENCODING_PCM_8BIT ? 3 : 2
      ]).cast<Uint8List>();
      __audioSource = audioSource;
      __sampleRate = sampleRate;
      __channelConfig = channelConfig;
      __audioFormat = audioFormat;
    }

    if (_microphone == null) {
      return Stream.error(StateError);
    }

    // sampleRate/bitDepth should be populated before any attempt to consume the stream externally.
    // configure these as Completers and listen to the stream internally before returning
    // these will complete only when this internal listener is called
    var _tmpSampleRateCompleter = _sampleRateCompleter;
    _sampleRateCompleter = new Completer();
    if (!_tmpSampleRateCompleter.isCompleted) {
      _tmpSampleRateCompleter.complete(_sampleRateCompleter.future);
    }

    var _tmpBitDepthCompleter = _bitDepthCompleter;
    _bitDepthCompleter = new Completer();
    if (!_tmpBitDepthCompleter.isCompleted) {
      _tmpBitDepthCompleter.complete(_bitDepthCompleter.future);
    }

    var _tmpBufferSizeCompleter = _bufferSizeCompleter;
    _bufferSizeCompleter = new Completer();
    if (!_tmpBufferSizeCompleter.isCompleted) {
      _tmpBufferSizeCompleter.complete(_bufferSizeCompleter.future);
    }

    late StreamSubscription<Uint8List> listener;
    listener = _microphone!.listen((x) async {
      listener.cancel();
      _sampleRateCompleter.complete((
          await _microphoneMethodChannel.invokeMethod("getSampleRate") as double).toInt());
      _bitDepthCompleter.complete(
          await _microphoneMethodChannel.invokeMethod("getBitDepth") as int);
      _bufferSizeCompleter.complete(
          await _microphoneMethodChannel.invokeMethod("getBufferSize") as int);
    });

    return _microphone!;
  }

  /// Updates flag to determine whether to request audio recording permission. Set to false to disable dialogue, set to true (default) to request permission if necessary
  static bool shouldRequestPermission(bool requestPermission) {
    return _requestPermission = requestPermission;
  }
}

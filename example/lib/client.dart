import 'generated/audioStream.pb.dart';
import 'generated/audioStream.pbgrpc.dart';

import 'package:grpc/grpc.dart';

import 'dart:typed_data';

class Client {
  ClientChannel channel;
  AudioProcessorClient stub;
  CallOptions options;

  static const HOST = '192.168.44.135';
  static const PORT = 12345;

  Client({String host: HOST, int port: PORT}) {
    channel = new ClientChannel(host, port: port, options: const ChannelOptions(credentials: const ChannelCredentials.insecure()));
    options = new CallOptions(timeout: Duration(seconds: 30));
    stub = new AudioProcessorClient(channel, options: options);
  }

  Stream<String> transcriptAudio(Stream<Uint8List> audio) async* {
    yield* _responseToString(stub.transcriptAudio(audio.map((audio) => _audioToSamples(audio))));
  }

  Stream<String> _responseToString(ResponseStream<dynamic> response) async* {
    yield* response.map((value) => value.word);
  }

  Samples _audioToSamples(List<int> input) {
    Samples samples = new Samples();
    samples.chunk = input;
    return samples;
  }
}
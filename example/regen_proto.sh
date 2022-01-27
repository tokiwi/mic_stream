#!/bin/bash

export PATH=$PATH:$HOME/.pub-cache/bin
mkdir -p lib/generated
exec protoc --dart_out=grpc:lib/generated -Iproto proto/audioStream.proto


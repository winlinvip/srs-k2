ARG ARCH

FROM ${ARCH}ossrs/k2:base3 AS build

WORKDIR /g

# Download models
RUN env GIT_LFS_SKIP_SMUDGE=1 \
    git clone https://huggingface.co/csukuangfj/sherpa-ncnn-streaming-zipformer-bilingual-zh-en-2023-02-13

RUN cd sherpa-ncnn-streaming-zipformer-bilingual-zh-en-2023-02-13 && \
    git lfs pull --include "*.bin" && \
    rm -rf .git

# Create files.
RUN mkdir -p /usr/local/k2 && \
    mv /g/sherpa-ncnn-streaming-zipformer-bilingual-zh-en-2023-02-13 /usr/local/k2/ && \
    ln -sf /usr/local/k2/sherpa-ncnn-streaming-zipformer-bilingual-zh-en-2023-02-13 /usr/local/k2/models

RUN mkdir -p /usr/local/k2/sherpa-ncnn/build/bin/ && \
    mv /g/sherpa-ncnn/build/bin/sherpa-ncnn* /usr/local/k2/sherpa-ncnn/build/bin/ && \
    strip /usr/local/k2/sherpa-ncnn/build/bin/sherpa-ncnn-ffmpeg && \
    ln -sf /usr/local/k2/sherpa-ncnn-streaming-zipformer-bilingual-zh-en-2023-02-13 /usr/local/k2/sherpa-ncnn/build/bin/models

# For sherpa requires libgomp.so.1
# /usr/lib/x86_64-linux-gnu/libgomp.so.1
# /usr/lib/x86_64-linux-gnu/libgomp.so.1.0.0
#RUN apt-get update -y && apt-get install -y libgomp1
RUN mkdir -p /usr/local/k2/lib && \
    cd /usr/local/k2/sherpa-ncnn/build/bin && \
    TARGET=$(ldd sherpa-ncnn-ffmpeg |grep libgomp |awk '{print $3}') && \
    cp $TARGET  $(realpath $TARGET) /usr/local/k2/lib/

FROM ${ARCH}ossrs/srs:5 AS srs

# Make SRS fit.
RUN rm -rf /usr/local/srs/objs/ffmpeg

FROM ${ARCH}golang:1.18 AS api

ADD api-server /g/api-server
WORKDIR /g/api-server
RUN go build -mod vendor . && \
    mkdir -p /usr/local/api && \
    mv api-server /usr/local/api/server

# http://releases.ubuntu.com/focal/
FROM ${ARCH}ubuntu:focal AS dist

# For SRS server.
COPY --from=srs /usr/local/srs /usr/local/srs
# For K2.
COPY --from=build /usr/local/k2 /usr/local/k2
# For api-server.
COPY --from=api /usr/local/api/server /usr/local/api/server

# The startup script.
ADD ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Expose ports for streaming @see https://github.com/ossrs/srs#ports
EXPOSE 1935 1985 8080 8000/udp 10080/udp

WORKDIR /usr/local/k2/sherpa-ncnn/build/bin

ENV PATH=$PATH:/usr/local/k2/sherpa-ncnn/build/bin \
  SRS_LISTEN=1935 \
  SRS_SRS_LOG_TANK=file \
  SRS_DAEMON=on \
  SRS_DISABLE_DAEMON_FOR_DOCKER=off \
  # For API.
  SRS_HTTP_API_ENABLED=on \
  SRS_HTTP_SERVER_ENABLED=on \
  SRS_EXPORTER_ENABLED=on \
  # For SRT.
  SRS_SRT_SERVER_ENABLED=on \
  SRS_SRT_SERVER_PEERLATENCY=0 \
  SRS_SRT_SERVER_RECVLATENCY=0 \
  SRS_SRT_SERVER_LATENCY=0 \
  SRS_SRT_SERVER_TSBPDMODE=off \
  SRS_SRT_SERVER_TLPKTDROP=off \
  SRS_VHOST_SRT_ENABLED=on \
  SRS_VHOST_SRT_TO_RTMP=on \
  # For WebRTC.
  SRS_RTC_SERVER_ENABLED=on \
  SRS_VHOST_RTC_ENABLED=on \
  SRS_VHOST_RTC_RTMP_TO_RTC=on \
  SRS_VHOST_RTC_RTC_TO_RTMP=on \
  # For SRS low latency.
  SRS_VHOST_TCP_NODELAY=on \
  SRS_VHOST_MIN_LATENCY=on \
  SRS_VHOST_PLAY_GOP_CACHE=off \
  # For SRS Hooks.
  SRS_VHOST_HTTP_HOOKS_ENABLED=on \
  SRS_VHOST_HTTP_HOOKS_ON_PUBLISH=http://localhost:8085/api/v1/streams \
  SRS_VHOST_HTTP_HOOKS_ON_UNPUBLISH=http://localhost:8085/api/v1/streams \
  # For API server
  API_SERVER_LISTEN=8085 \
  API_SERVER_K2=sherpa-ncnn-ffmpeg \
  API_SERVER_K2_DIR=/usr/local/k2/sherpa-ncnn/build/bin \
  # For sherpa.
  SHERPA_NCNN_TOKENS=./models/tokens.txt \
  SHERPA_NCNN_ENCODER_PARAM=./models/encoder_jit_trace-pnnx.ncnn.param \
  SHERPA_NCNN_ENCODER_BIN=./models/encoder_jit_trace-pnnx.ncnn.bin \
  SHERPA_NCNN_DECODER_PARAM=./models/decoder_jit_trace-pnnx.ncnn.param \
  SHERPA_NCNN_DECODER_BIN=./models/decoder_jit_trace-pnnx.ncnn.bin \
  SHERPA_NCNN_JOINER_PARAM=./models/joiner_jit_trace-pnnx.ncnn.param \
  SHERPA_NCNN_JOINER_BIN=./models/joiner_jit_trace-pnnx.ncnn.bin \
  SHERPA_NCNN_INPUT_URL=rtmp://localhost/live/livestream \
  SHERPA_NCNN_NUM_THREADS=4 \
  SHERPA_NCNN_METHOD=greedy_search \
  SHERPA_NCNN_ENABLE_ENDPOINT=on \
  SHERPA_NCNN_RULE1_MIN_TRAILING_SILENCE=1.5 \
  SHERPA_NCNN_RULE2_MIN_TRAILING_SILENCE=0.8 \
  SHERPA_NCNN_RULE3_MIN_UTTERANCE_LENGTH=15 \
  SHERPA_NCNN_SIMPLE_DISLAY=on \
  SHERPA_NCNN_DISPLAY_LABEL=Data \
  LD_LIBRARY_PATH=/usr/local/k2/lib/

ENTRYPOINT ["docker-entrypoint.sh"]

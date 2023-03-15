ARG ARCH

FROM ${ARCH}ossrs/ubuntu:focal AS build

# https://serverfault.com/questions/949991/how-to-install-tzdata-on-a-ubuntu-docker-image
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get install -y gcc g++ make autoconf automake cmake git git-lfs

WORKDIR /g

# Build ffmpeg 5.1
RUN apt-get install -y pkg-config nasm

RUN git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg && \
    cd ffmpeg && git checkout n5.1.2 && \
    ./configure && make -j2 && make install

# Build sherpa-ncnn
RUN git clone https://github.com/k2-fsa/sherpa-ncnn && \
    mkdir -p sherpa-ncnn/build && \
    cd sherpa-ncnn/build && \
    cmake -DCMAKE_BUILD_TYPE=Release -DSHERPA_NCNN_ENABLE_FFMPEG_EXAMPLES=ON .. && \
    make -j2

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

# http://releases.ubuntu.com/focal/
FROM ${ARCH}ubuntu:focal AS dist

# For SRS server.
COPY --from=srs /usr/local/srs /usr/local/srs
# For K2.
COPY --from=build /usr/local/k2 /usr/local/k2

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
  LD_LIBRARY_PATH=/usr/local/k2/lib/

ENTRYPOINT ["docker-entrypoint.sh"]
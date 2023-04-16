#!/bin/bash

#  Allow user to control the entrypoint.
if [[ $1 == bash || $1 == sh ]]; then
  exec "$@"
  exit $?
fi

# Always start SRS by default.
(cd /usr/local/srs && ./objs/srs -c conf/srs.conf 1>/dev/stderr 2>/dev/stderr)

# Run sherpa.
echo "$@"
echo -n "SHERPA_NCNN_TOKENS=$SHERPA_NCNN_TOKENS, SHERPA_NCNN_ENCODER_PARAM=$SHERPA_NCNN_ENCODER_PARAM, "
echo -n "SHERPA_NCNN_ENCODER_BIN=$SHERPA_NCNN_ENCODER_BIN, SHERPA_NCNN_DECODER_PARAM=$SHERPA_NCNN_DECODER_PARAM, "
echo -n "SHERPA_NCNN_DECODER_BIN=$SHERPA_NCNN_DECODER_BIN, SHERPA_NCNN_JOINER_PARAM=$SHERPA_NCNN_JOINER_PARAM, "
echo -n "SHERPA_NCNN_JOINER_BIN=$SHERPA_NCNN_JOINER_BIN, SHERPA_NCNN_INPUT_URL=$SHERPA_NCNN_INPUT_URL, "
echo -n "SHERPA_NCNN_NUM_THREADS=$SHERPA_NCNN_NUM_THREADS, SHERPA_NCNN_METHOD=$SHERPA_NCNN_METHOD, "
echo -n "SHERPA_NCNN_ENABLE_ENDPOINT=$SHERPA_NCNN_ENABLE_ENDPOINT, "
echo -n "SHERPA_NCNN_RULE1_MIN_TRAILING_SILENCE=$SHERPA_NCNN_RULE1_MIN_TRAILING_SILENCE, "
echo -n "SHERPA_NCNN_RULE2_MIN_TRAILING_SILENCE=$SHERPA_NCNN_RULE2_MIN_TRAILING_SILENCE, "
echo -n "SHERPA_NCNN_RULE3_MIN_UTTERANCE_LENGTH=$SHERPA_NCNN_RULE3_MIN_UTTERANCE_LENGTH, "
echo "SHERPA_NCNN_SIMPLE_DISLAY=$SHERPA_NCNN_SIMPLE_DISLAY"

# Tips.
echo ""
echo "---------------------------------------------"
echo "You can push RTMP stream to SRS by FFmpeg:"
echo "    rtmp://localhost/live/livestream"
echo "Or by OBS:"
echo "    Server:     rtmp://localhost/live"
echo "    Stream Key: livestream"
echo "---------------------------------------------"
echo ""

# We use api server to start K2.
set -- /usr/local/api/server "$@"
exec "$@"

# srs-k2

[![](https://img.shields.io/twitter/follow/srs_server?style=social)](https://twitter.com/srs_server)
[![](https://badgen.net/discord/members/yZ4BnPmHAd)](https://discord.gg/yZ4BnPmHAd)
[![](https://ossrs.net/wiki/images/do-btn-srs-125x20.svg)](https://cloud.digitalocean.com/droplets/new?appId=104916642&size=s-1vcpu-1gb&region=sgp1&image=ossrs-srs&type=applications)

This is a demonstration for applying [k2-fsa/sherpa-ncnn](https://github.com/k2-fsa/sherpa-ncnn) to live streaming
and WebRTC by SRS.

It's not bound to SRS, so you're able to use other media servers, or use microphone or device as audio source of 
FFmpeg, for example, use FFmpeg to pull IPC/microphone/RTMP/RTSP/UDP stream and converting to text.

The workflow is like this, the original picture is [here](https://www.figma.com/file/6PB2d9yxbhdoqdW8iPIyzY)

```text
+------------+                          +------------------------+
| Microphone +---------->---------------+ sherpa-ncnn-microphone +--+
+-----+------+                          +------------------------+  |
      |                                                             +--> Text
      |   +---------+     +------------+    +--------------------+  |
      +->-+   OBS   +-->--+  SRS Cloud +-->-+ sherpa-ncnn-ffmpeg +--+
          +---------+     +-----+------+    +--------------------+ 
```

## Usage: OBS

First, run in docker:

```bash
docker run --rm -it -p 1935:1935 -p 1985:1985 -p 8080:8080 ossrs/k2:1
```

> Note: Please use `registry.cn-hangzhou.aliyuncs.com/ossrs/k2:1` if in China.

Then, publish by OBS:

* Server: `rtmp://localhost/live/`
* Stream Key: `livestream`

Or, publish microphone by ffmpeg for macOS:

```bash
ffmpeg -f avfoundation -i ":0" -acodec aac -ab 64k -ar 44100 -ac 2 \
  -f flv rtmp://localhost/live/livestream
```

> Note: Use `ffmpeg -f avfoundation -list_devices true -i ""` to list microphones.

## Usage: URL

If you got a FFmpeg URL, you can set the env `SHERPA_NCNN_INPUT_URL`:

```bash
docker run --rm --env SHERPA_NCNN_INPUT_URL=url ossrs/k2:1
```

Please note that the `url` can be any URL that supported by FFmpeg, for example:

* RTMP: `rtmp://192.168.1.100/live/livestream`
* HLS: `htto://192.168.1.100:8080/live/livestream.m3u8`
* HTTP-FLV: `htto://192.168.1.100:8080/live/livestream.flv`

Or any other format supported by FFmpeg.

## Usage: WebRTC

First, get your ip by `ifconfig`, for example `192.168.6.53`:

```bash
ifconfig en0 |grep 'inet '
#	inet 192.168.6.53 netmask 0xffffff00 broadcast 192.168.6.255
```

Next, start docker with IP setting:

```bash
docker run --rm -it -p 1935:1935 -p 1985:1985 -p 8080:8080 -p 8000:8000/udp \
    --env CANDIDATE="192.168.6.53" ossrs/k2:1
```

> Note: Please use `registry.cn-hangzhou.aliyuncs.com/ossrs/k2:1` if in China.

Then open the web page:

http://localhost:8080/players/rtc_publisher.html

Click the button and it starts to work like magic.


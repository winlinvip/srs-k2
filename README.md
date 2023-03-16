# srs-k2

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


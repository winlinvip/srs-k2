package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/ossrs/go-oryx-lib/logger"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"github.com/ossrs/go-oryx-lib/errors"
)

func main() {
	ctx := context.Background()
	if err := doMain(ctx); err != nil {
		panic(err)
	}
}

func doMain(ctx context.Context) error {
	ctx, cancel := context.WithCancel(ctx)

	if os.Getenv("API_SERVER_LISTEN") == "" {
		os.Setenv("API_SERVER_LISTEN", "8085")
	}
	logger.Tf(ctx, "API server API_SERVER_LISTEN=%v, API_SERVER_K2=%v, API_SERVER_K2_DIR=%v",
		os.Getenv("API_SERVER_LISTEN"), os.Getenv("API_SERVER_K2"), os.Getenv("API_SERVER_K2_DIR"))

	flag.Usage = func() {
		fmt.Println("A demo api-server for SRS\n")
		fmt.Println(fmt.Sprintf("Usage: %v", os.Args[0]))
		fmt.Println(fmt.Sprintf("    API_SERVER_LISTEN=8085             The listen port for API server"))
		fmt.Println(fmt.Sprintf("    API_SERVER_K2=sherpa-ncnn-ffmpeg   The K2 tool for ASR, empty to ignore"))
	}
	flag.Parse()


	// Start sherpa-ncnn-ffmpeg process.
	var cmd *exec.Cmd
	if os.Getenv("API_SERVER_K2") != "" {
		cmd = exec.CommandContext(ctx, os.Getenv("API_SERVER_K2"))
		cmd.Dir = os.Getenv("API_SERVER_K2_DIR")

		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return errors.Wrapf(err, "pipe stdout")
		}

		stderr, err := cmd.StderrPipe()
		if err != nil {
			return errors.Wrapf(err, "pipe stderr")
		}

		if err = cmd.Start(); err != nil {
			return errors.Wrapf(err, "start")
		}

		go func() {
			defer cancel()

			buf := make([]byte, 4096)
			for {
				if nn, err := stdout.Read(buf); err != nil {
					if err != io.EOF {
						logger.Ef(ctx, "err %+v", err)
					}
					return
				} else {
					fmt.Print(string(buf[:nn]))
				}
			}
		}()

		go func() {
			defer cancel()

			buf := make([]byte, 4096)
			for {
				if nn, err := stderr.Read(buf); err != nil {
					if err != io.EOF {
						logger.Ef(ctx, "err %+v", err)
					}
					return
				} else {
					fmt.Print(string(buf[:nn]))
				}
			}
		}()
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("HelloWorld"))
	})

	// handle the streams requests: publish/unpublish stream.
	http.HandleFunc("/api/v1/streams", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			SrsWriteDataResponse(w, struct{}{})
			return
		}

		if err := func() error {
			body, err := ioutil.ReadAll(r.Body)
			if err != nil {
				return fmt.Errorf("read request body, err %v", err)
			}

			msg := &SrsStreamRequest{}
			if err := json.Unmarshal(body, msg); err != nil {
				return fmt.Errorf("parse message from %v, err %v", string(body), err)
			}
			if msg.Action == "on_publish" {
				logger.Tf(ctx, "User publish stream %v/%v", msg.App, msg.Stream)
			} else {
				// Notify K2 to handle the unpublish event.
				if cmd != nil && cmd.Process != nil {
					syscall.Kill(cmd.Process.Pid, syscall.SIGUSR1)
					time.Sleep(100 * time.Millisecond)
				}

				logger.Tf(ctx, "User unpublish stream %v/%v", msg.App, msg.Stream)
			}

			if !msg.IsOnPublish() && !msg.IsOnUnPublish() {
				return fmt.Errorf("invalid message %v", msg.String())
			}

			SrsWriteDataResponse(w, &SrsCommonResponse{Code: 0})
			return nil
		}(); err != nil {
			SrsWriteErrorResponse(w, err)
		}
	})

	addr := strings.ReplaceAll(fmt.Sprintf(":%v", os.Getenv("API_SERVER_LISTEN")), "::", ":")
	logger.Tf(ctx, "API server listen at %v", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		return errors.Wrapf(err, "api listen")
	}

	return nil
}

type SrsCommonResponse struct {
	Code int         `json:"code"`
	Data interface{} `json:"data"`
}

func SrsWriteErrorResponse(w http.ResponseWriter, err error) {
	w.WriteHeader(http.StatusInternalServerError)
	w.Write([]byte(err.Error()))
}

func SrsWriteDataResponse(w http.ResponseWriter, data interface{}) {
	j, err := json.Marshal(data)
	if err != nil {
		SrsWriteErrorResponse(w, fmt.Errorf("marshal %v, err %v", err))
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(j)
}

// SrsCommonRequest is the common fields of request messages from SRS HTTP callback.
type SrsCommonRequest struct {
	Action   string `json:"action"`
	ClientId string `json:"client_id"`
	Ip       string `json:"ip"`
	Vhost    string `json:"vhost"`
	App      string `json:"app"`
}

func (v *SrsCommonRequest) String() string {
	return fmt.Sprintf("action=%v, client_id=%v, ip=%v, vhost=%v", v.Action, v.ClientId, v.Ip, v.Vhost)
}

/*
for SRS hook: on_publish/on_unpublish
on_publish:
   when client(encoder) publish to vhost/app/stream, call the hook,
   the request in the POST data string is a object encode by json:
		 {
			 "action": "on_publish",
			 "client_id": "9308h583",
			 "ip": "192.168.1.10",
			 "vhost": "video.test.com",
			 "app": "live",
			 "stream": "livestream",
			 "param":"?token=xxx&salt=yyy"
		 }
on_unpublish:
   when client(encoder) stop publish to vhost/app/stream, call the hook,
   the request in the POST data string is a object encode by json:
		 {
			 "action": "on_unpublish",
			 "client_id": "9308h583",
			 "ip": "192.168.1.10",
			 "vhost": "video.test.com",
			 "app": "live",
			 "stream": "livestream",
			 "param":"?token=xxx&salt=yyy"
		 }
if valid, the hook must return HTTP code 200(Stauts OK) and response
an int value specifies the error code(0 corresponding to success):
	 0
*/
type SrsStreamRequest struct {
	SrsCommonRequest
	Stream string `json:"stream"`
	Param  string `json:"param"`
}

func (v *SrsStreamRequest) String() string {
	var sb strings.Builder
	sb.WriteString(v.SrsCommonRequest.String())
	if v.IsOnPublish() || v.IsOnUnPublish() {
		sb.WriteString(fmt.Sprintf(", stream=%v, param=%v", v.Stream, v.Param))
	}
	return sb.String()
}

func (v *SrsStreamRequest) IsOnPublish() bool {
	return v.Action == "on_publish"
}

func (v *SrsStreamRequest) IsOnUnPublish() bool {
	return v.Action == "on_unpublish"
}

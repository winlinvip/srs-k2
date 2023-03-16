package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
)

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

func main() {
	srsBin := os.Args[0]
	if strings.HasPrefix(srsBin, "/var") {
		srsBin = "go run ."
	}

	var port int
	flag.IntVar(&port, "p", 8085, "HTTP listen port. Default is 8085")
	flag.Usage = func() {
		fmt.Println("A demo api-server for SRS\n")
		fmt.Println(fmt.Sprintf("Usage: %v [flags]", srsBin))
		flag.PrintDefaults()
		fmt.Println(fmt.Sprintf("For example:"))
		fmt.Println(fmt.Sprintf(" 		%v -p 8085", srsBin))
	}
	flag.Parse()

	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)

	// check if only one number arg
	if len(os.Args[1:]) == 1 {
		portArg := os.Args[1]
		var err error
		if port, err = strconv.Atoi(portArg); err != nil {
			log.Println(fmt.Sprintf("parse port arg:%v to int failed, err %v", portArg, err))
			flag.Usage()
			os.Exit(1)
		}
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
				log.Println(fmt.Sprintf("User publish stream %v/%v", msg.App, msg.Stream))
			} else {
				log.Println(fmt.Sprintf("User unpublish stream %v/%v", msg.App, msg.Stream))
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

	addr := fmt.Sprintf(":%v", port)
	log.Println(fmt.Sprintf("API server listen at %v", addr))
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Println(fmt.Sprintf("listen on addr:%v failed, err is %v", addr, err))
	}
}

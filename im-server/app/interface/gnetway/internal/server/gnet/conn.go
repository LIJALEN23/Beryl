// Copyright 2022 Teamgram Authors
//  All rights reserved.
//
// Author: Benqi (wubenqi@gmail.com)
//

package gnet

import (
	"bytes"

	"github.com/teamgram/teamgram-server/app/interface/gnetway/internal/server/gnet/codec"
	httpcodec "github.com/teamgram/teamgram-server/app/interface/gnetway/internal/server/gnet/http"
	"github.com/teamgram/teamgram-server/app/interface/gnetway/internal/server/gnet/ws"

	"github.com/zeromicro/go-zero/core/jsonx"
	"github.com/zeromicro/go-zero/core/logx"
)

type HandshakeStateCtx struct {
	State         int32  `json:"state,omitempty"`
	ResState      int32  `json:"res_state,omitempty"`
	Nonce         []byte `json:"nonce,omitempty"`
	ServerNonce   []byte `json:"server_nonce,omitempty"`
	NewNonce      []byte `json:"new_nonce,omitempty"`
	A             []byte `json:"a,omitempty"`
	P             []byte `json:"p,omitempty"`
	HandshakeType int    `json:"handshake_type"`
	ExpiresIn     int32  `json:"expires_in,omitempty"`
}

func (m *HandshakeStateCtx) DebugString() string {
	s, _ := jsonx.MarshalToString(m)
	return s
}

type connContext struct {
	codec      codec.Codec
	authKey    *authKeyUtil
	sessionId  int64
	handshakes []*HandshakeStateCtx
	clientIp   string
	tcp        bool
	websocket  bool
	http       bool
	wsCodec    *ws.WsCodec
	httpCodec  *httpcodec.HttpCodec
	logx.Logger
	newSession bool
	nextSeqNo  int32
	closeDate  int64
	ppv1       bool
}

func newConnContext() *connContext {
	return &connContext{
		codec:    nil,
		clientIp: "",
	}
}

func (ctx *connContext) generateMessageSeqNo(increment bool) int32 {
	value := ctx.nextSeqNo
	if increment {
		ctx.nextSeqNo++
		return value*2 + 1
	} else {
		return value * 2
	}
}

func (ctx *connContext) setClientIp(ip string) {
	ctx.clientIp = ip
}

func (ctx *connContext) getAuthKey() *authKeyUtil {
	return ctx.authKey
}

func (ctx *connContext) putAuthKey(k *authKeyUtil) {
	ctx.authKey = k
}

func (ctx *connContext) getHandshakeStateCtx(nonce []byte) *HandshakeStateCtx {
	for _, state := range ctx.handshakes {
		if bytes.Equal(nonce, state.Nonce) {
			return state
		}
	}

	return nil
}

const maxHandshakes = 3

func (ctx *connContext) putHandshakeStateCt(state *HandshakeStateCtx) {
	if len(ctx.handshakes) >= maxHandshakes {
		// Evict oldest handshake to prevent unbounded growth
		copy(ctx.handshakes, ctx.handshakes[1:])
		ctx.handshakes[len(ctx.handshakes)-1] = state
		return
	}
	ctx.handshakes = append(ctx.handshakes, state)
}

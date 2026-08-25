// Copyright (c) 2021-present,  Teamgram Studio (https://teamgram.io).
//  All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package gnet

import (
	"encoding/hex"
	"fmt"

	"github.com/teamgram/proto/mtproto"
)

type CacheV struct {
	V *mtproto.AuthKeyInfo
}

func (c CacheV) Size() int {
	return 1
}

func (s *Server) GetAuthKey(authKeyId int64) *mtproto.AuthKeyInfo {
	var (
		cacheK = fmt.Sprintf("%d", authKeyId)
		value  *CacheV
	)

	if v, ok := s.cache.Get(cacheK); ok {
		value = v.(*CacheV)
	}

	if value == nil {
		return nil
	} else {
		return value.V
	}
}

func (s *Server) PutAuthKey(keyInfo *mtproto.AuthKeyInfo) {
	var (
		cacheK = fmt.Sprintf("%d", keyInfo.AuthKeyId)
	)

	// TODO: expires_in
	s.cache.Set(cacheK, &CacheV{V: keyInfo})
}

// HandshakeCacheV wraps HandshakeStateCtx for LRU cache storage.
type HandshakeCacheV struct {
	State *HandshakeStateCtx
}

func (c HandshakeCacheV) Size() int {
	return 1
}

// GetHttpHandshakeState retrieves handshake state from cache by nonce (for HTTP transport).
func (s *Server) GetHttpHandshakeState(nonce []byte) *HandshakeStateCtx {
	key := "hs:" + hex.EncodeToString(nonce)
	if v, ok := s.cache.Get(key); ok {
		return v.(*HandshakeCacheV).State
	}
	return nil
}

// PutHttpHandshakeState stores handshake state in cache by nonce (for HTTP transport).
func (s *Server) PutHttpHandshakeState(state *HandshakeStateCtx) {
	key := "hs:" + hex.EncodeToString(state.Nonce)
	s.cache.Set(key, &HandshakeCacheV{State: state})
}

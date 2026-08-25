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
	"sync"

	"github.com/zeromicro/go-zero/core/logx"
)

const authSessionShardCount = 256

type sessionData struct {
	sessionId int64
	connIds   map[int64]struct{}
}

type authSession struct {
	authKey     *authKeyUtil
	sessionList map[int64]sessionData
}

type authSessionShard struct {
	sync.RWMutex
	sessions map[int64]*authSession
}

type authSessionManager struct {
	shards [authSessionShardCount]authSessionShard
}

func NewAuthSessionManager() *authSessionManager {
	m := &authSessionManager{}
	for i := range m.shards {
		m.shards[i].sessions = make(map[int64]*authSession)
	}
	return m
}

func (m *authSessionManager) getShard(authKeyId int64) *authSessionShard {
	return &m.shards[uint64(authKeyId)%authSessionShardCount]
}

func (m *authSessionManager) AddNewSession(authKey *authKeyUtil, sessionId int64, connId int64) (bNew bool) {
	logx.Debugf("addNewSession: auth_key_id: %d, session_id: %d, conn_id: %d",
		authKey.AuthKeyId(),
		sessionId,
		connId)

	shard := m.getShard(authKey.AuthKeyId())
	shard.Lock()
	defer shard.Unlock()

	if v, ok := shard.sessions[authKey.AuthKeyId()]; ok {
		if v2, ok2 := v.sessionList[sessionId]; ok2 {
			if _, exists := v2.connIds[connId]; !exists {
				v2.connIds[connId] = struct{}{}
			}
		} else {
			s := sessionData{
				sessionId: sessionId,
				connIds:   map[int64]struct{}{connId: {}},
			}
			v.sessionList[sessionId] = s
			bNew = true
		}
	} else {
		s := sessionData{
			sessionId: sessionId,
			connIds:   map[int64]struct{}{connId: {}},
		}

		shard.sessions[authKey.AuthKeyId()] = &authSession{
			authKey: authKey,
			sessionList: map[int64]sessionData{
				sessionId: s,
			},
		}
		bNew = true
	}
	return
}

func (m *authSessionManager) RemoveSession(authKeyId, sessionId int64, connId int64) (bDeleted bool) {
	logx.Debugf("removeSession: auth_key_id: %d, session_id: %d, conn_id: %d",
		authKeyId,
		sessionId,
		connId)

	shard := m.getShard(authKeyId)
	shard.Lock()
	defer shard.Unlock()

	if v, ok := shard.sessions[authKeyId]; ok {
		if v2, ok2 := v.sessionList[sessionId]; ok2 {
			delete(v2.connIds, connId)
			if len(v2.connIds) == 0 {
				delete(v.sessionList, sessionId)
				bDeleted = true
			}
			if len(v.sessionList) == 0 {
				delete(shard.sessions, authKeyId)
			}
		}
	}

	return
}

func (m *authSessionManager) FoundSessionConnId(authKeyId, sessionId int64) (*authKeyUtil, []int64) {
	shard := m.getShard(authKeyId)
	shard.RLock()
	defer shard.RUnlock()

	if v, ok := shard.sessions[authKeyId]; ok {
		if v2, ok2 := v.sessionList[sessionId]; ok2 {
			connIdList := make([]int64, 0, len(v2.connIds))
			for id := range v2.connIds {
				connIdList = append(connIdList, id)
			}
			return v.authKey, connIdList
		}
	}

	return nil, nil
}

// Copyright 2022 Teamgram Authors
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
//
// Author: teamgramio (teamgram.io@gmail.com)
//

package core

import (
	"github.com/teamgram/proto/mtproto"
	"github.com/teamgram/teamgram-server/app/service/biz/user/user"
)

// AccountSetAuthorizationTTL
// account.setAuthorizationTTL#bf899aa0 authorization_ttl_days:int = Bool;
func (c *AuthorizationCore) AccountSetAuthorizationTTL(in *mtproto.TLAccountSetAuthorizationTTL) (*mtproto.Bool, error) {
	value := in.GetAuthorizationTtlDays()
	switch value {
	case 30:
	case 90:
	case 180:
	case 182:
	case 183:
	case 365:
	case 548:
	case 730:
	default:
		// err := mtproto.ErrTtlDaysInvalid
		c.Logger.Errorf("account.setAuthorizationTTL - error: %s", in)
		// return nil, err
	}

	_, _ = c.svcCtx.Dao.UserClient.UserSetAuthorizationTTL(
		c.ctx,
		&user.TLUserSetAuthorizationTTL{
			UserId: c.MD.UserId,
			Ttl:    in.AuthorizationTtlDays,
		})
	return mtproto.BoolTrue, nil
}

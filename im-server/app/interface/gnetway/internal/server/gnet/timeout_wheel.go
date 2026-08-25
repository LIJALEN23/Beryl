// Copyright (c) 2026 The Teamgram Authors (https://teamgram.net).
//  All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package gnet

import "sync"

// timeoutWheel manages connection timeouts using a bucketed time wheel.
// Instead of iterating all connections every tick, only the current expired
// bucket is scanned, reducing CPU overhead from O(N) to O(N/numSlots) per tick.
//
// Each slot covers `slotDuration` seconds. Connections are placed into the
// slot corresponding to their closeDate. On each tick, the wheel advances
// and expires all connections in the current slot.

const (
	wheelSlotDuration = 10 // seconds per slot
	wheelNumSlots     = 64 // covers ~640 seconds, enough for 300+10s timeout
)

type timeoutWheel struct {
	mu    sync.Mutex
	slots [wheelNumSlots]map[int64]struct{} // connId sets per slot
	pos   int                               // current slot position
}

func newTimeoutWheel() *timeoutWheel {
	tw := &timeoutWheel{}
	for i := range tw.slots {
		tw.slots[i] = make(map[int64]struct{})
	}
	return tw
}

// slotIndex returns the slot index for a given unix timestamp.
func slotIndex(unixSec int64) int {
	return int((unixSec / wheelSlotDuration) % wheelNumSlots)
}

// Add registers a connection in the slot for the given deadline.
func (tw *timeoutWheel) Add(connId int64, closeDate int64) {
	idx := slotIndex(closeDate)
	tw.mu.Lock()
	tw.slots[idx][connId] = struct{}{}
	tw.mu.Unlock()
}

// Remove removes a connection from the slot for the given deadline.
func (tw *timeoutWheel) Remove(connId int64, closeDate int64) {
	idx := slotIndex(closeDate)
	tw.mu.Lock()
	delete(tw.slots[idx], connId)
	tw.mu.Unlock()
}

// Move moves a connection from oldDeadline slot to newDeadline slot.
// If both map to the same slot, this is a no-op.
func (tw *timeoutWheel) Move(connId int64, oldDeadline, newDeadline int64) {
	oldIdx := slotIndex(oldDeadline)
	newIdx := slotIndex(newDeadline)
	if oldIdx == newIdx {
		return
	}
	tw.mu.Lock()
	delete(tw.slots[oldIdx], connId)
	tw.slots[newIdx][connId] = struct{}{}
	tw.mu.Unlock()
}

// ExpireSlot returns all connection IDs in the slot for the given time and clears that slot.
// Returns nil if the slot is empty.
func (tw *timeoutWheel) ExpireSlot(now int64) []int64 {
	idx := slotIndex(now)
	tw.mu.Lock()
	slot := tw.slots[idx]
	if len(slot) == 0 {
		tw.mu.Unlock()
		return nil
	}
	// Collect and clear
	connIds := make([]int64, 0, len(slot))
	for id := range slot {
		connIds = append(connIds, id)
	}
	tw.slots[idx] = make(map[int64]struct{})
	tw.mu.Unlock()
	return connIds
}

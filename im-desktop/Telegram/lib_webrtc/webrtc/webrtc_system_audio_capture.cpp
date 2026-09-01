// This file is part of Desktop App Toolkit,
// a set of libraries for developing nice desktop applications.
//
// For license and copyright information please follow this link:
// https://github.com/desktop-app/legal/blob/master/LEGAL
//
#include "webrtc/webrtc_system_audio_capture.h"

#ifdef WEBRTC_LINUX
#include "webrtc/platform/linux/webrtc_system_audio_capture_linux.h"
#endif // WEBRTC_LINUX

#include <utility>

namespace Webrtc {

bool SystemAudioCaptureSupported() {
#ifdef WEBRTC_LINUX
	return details::SystemAudioCaptureLinux::IsSupported();
#else // WEBRTC_LINUX
	return false;
#endif // !WEBRTC_LINUX
}

std::unique_ptr<SystemAudioCapture> CreateSystemAudioCapture(
		SystemAudioSamplesCallback callback) {
#ifdef WEBRTC_LINUX
	if (!details::SystemAudioCaptureLinux::IsSupported()) {
		return nullptr;
	}
	return std::make_unique<details::SystemAudioCaptureLinux>(
		std::move(callback));
#else // WEBRTC_LINUX
	return nullptr;
#endif // !WEBRTC_LINUX
}

} // namespace Webrtc

// Copyright 2024 Teamgram Authors
//  All rights reserved.
//
// Author: Benqi (wubenqi@gmail.com)
//

package http

import (
	"bytes"
	"fmt"
	"strconv"

	"github.com/panjf2000/gnet/v2"
)

const (
	maxContentLength = 1 * 1024 * 1024 // 1MB max body
)

type parseState int

const (
	stateReadingHeaders parseState = iota
	stateReadingBody
)

type HttpCodec struct {
	buf        bytes.Buffer
	state      parseState
	method     string
	path       string
	contentLen int
	headerLen  int // offset where body starts
}

// ReadBufferBytes reads available bytes from the connection into the internal buffer.
func (h *HttpCodec) ReadBufferBytes(c gnet.Conn) gnet.Action {
	data, err := c.Peek(-1)
	if err != nil {
		return gnet.Close
	}
	if len(data) == 0 {
		return gnet.None
	}
	h.buf.Write(data)
	_, _ = c.Discard(len(data))
	return gnet.None
}

// ParseRequest attempts to parse a complete HTTP request from the buffer.
// Returns (body, done, err). If done is false, more data is needed.
func (h *HttpCodec) ParseRequest() (body []byte, done bool, err error) {
	if h.state == stateReadingHeaders {
		data := h.buf.Bytes()
		idx := bytes.Index(data, []byte("\r\n\r\n"))
		if idx < 0 {
			if len(data) > 8192 {
				return nil, false, fmt.Errorf("headers too large")
			}
			return nil, false, nil
		}

		headerBytes := data[:idx]
		h.headerLen = idx + 4

		// Parse request line
		lineEnd := bytes.Index(headerBytes, []byte("\r\n"))
		if lineEnd < 0 {
			return nil, false, fmt.Errorf("invalid HTTP request line")
		}
		requestLine := string(headerBytes[:lineEnd])
		parts := bytes.Fields([]byte(requestLine))
		if len(parts) < 3 {
			return nil, false, fmt.Errorf("invalid HTTP request line")
		}
		h.method = string(parts[0])
		h.path = string(parts[1])

		// Parse Content-Length from headers
		h.contentLen = 0
		headers := headerBytes[lineEnd+2:]
		for len(headers) > 0 {
			end := bytes.Index(headers, []byte("\r\n"))
			var line []byte
			if end < 0 {
				line = headers
				headers = nil
			} else {
				line = headers[:end]
				headers = headers[end+2:]
			}
			if len(line) > 16 && (line[0] == 'C' || line[0] == 'c') {
				lower := bytes.ToLower(line[:15])
				if bytes.HasPrefix(lower, []byte("content-length:")) {
					valStr := bytes.TrimSpace(line[15:])
					cl, e := strconv.Atoi(string(valStr))
					if e != nil {
						return nil, false, fmt.Errorf("invalid Content-Length")
					}
					h.contentLen = cl
				}
			}
		}

		if h.contentLen > maxContentLength {
			return nil, false, fmt.Errorf("content too large")
		}

		h.state = stateReadingBody
	}

	// stateReadingBody
	totalNeeded := h.headerLen + h.contentLen
	if h.buf.Len() < totalNeeded {
		return nil, false, nil
	}

	// Extract body
	all := h.buf.Bytes()
	body = make([]byte, h.contentLen)
	copy(body, all[h.headerLen:totalNeeded])
	return body, true, nil
}

// Method returns the parsed HTTP method.
func (h *HttpCodec) Method() string {
	return h.method
}

// Path returns the parsed HTTP path.
func (h *HttpCodec) Path() string {
	return h.path
}

// Reset clears consumed data and resets state for the next request (keep-alive).
func (h *HttpCodec) Reset() {
	totalConsumed := h.headerLen + h.contentLen
	remaining := h.buf.Bytes()[totalConsumed:]
	h.buf.Reset()
	if len(remaining) > 0 {
		h.buf.Write(remaining)
	}
	h.state = stateReadingHeaders
	h.method = ""
	h.path = ""
	h.contentLen = 0
	h.headerLen = 0
}

var (
	responseHeaders = []byte("HTTP/1.1 200 OK\r\n" +
		"Access-Control-Allow-Headers: origin, content-type\r\n" +
		"Access-Control-Allow-Methods: POST, OPTIONS\r\n" +
		"Access-Control-Allow-Origin: *\r\n" +
		"Access-Control-Max-Age: 1728000\r\n" +
		"Cache-control: no-store\r\n" +
		"Connection: keep-alive\r\n" +
		"Content-type: application/octet-stream\r\n" +
		"Pragma: no-cache\r\n" +
		"Strict-Transport-Security: max-age=15768000\r\n")

	corsResponseHeaders = []byte("HTTP/1.1 200 OK\r\n" +
		"Access-Control-Allow-Headers: origin, content-type\r\n" +
		"Access-Control-Allow-Methods: POST, OPTIONS\r\n" +
		"Access-Control-Allow-Origin: *\r\n" +
		"Access-Control-Max-Age: 1728000\r\n" +
		"Connection: keep-alive\r\n" +
		"Content-Length: 0\r\n\r\n")
)

// FormatResponse formats an HTTP 200 response with the given payload.
func FormatResponse(payload []byte) []byte {
	cl := strconv.Itoa(len(payload))
	buf := make([]byte, 0, len(responseHeaders)+16+len(cl)+4+len(payload))
	buf = append(buf, responseHeaders...)
	buf = append(buf, "Content-Length: "...)
	buf = append(buf, cl...)
	buf = append(buf, "\r\n\r\n"...)
	buf = append(buf, payload...)
	return buf
}

// FormatCORSResponse returns a pre-built CORS preflight response.
func FormatCORSResponse() []byte {
	return corsResponseHeaders
}

// FormatErrorResponse formats an HTTP error response.
func FormatErrorResponse(code int, msg string) []byte {
	status := strconv.Itoa(code)
	body := []byte(msg)
	cl := strconv.Itoa(len(body))
	var buf bytes.Buffer
	buf.WriteString("HTTP/1.1 ")
	buf.WriteString(status)
	buf.WriteByte(' ')
	buf.WriteString(msg)
	buf.WriteString("\r\nConnection: close\r\nContent-Length: ")
	buf.WriteString(cl)
	buf.WriteString("\r\n\r\n")
	buf.Write(body)
	return buf.Bytes()
}

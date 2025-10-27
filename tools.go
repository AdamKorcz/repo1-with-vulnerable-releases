//go:build tools
// +build tools

package tools

import (
	_ "golang.org/x/text/language"
	_ "github.com/gorilla/websocket"
	_ "golang.org/x/net/html"
	_ "golang.org/x/crypto/ssh"
	_ "github.com/gin-gonic/gin"
	_ "github.com/golang-jwt/jwt/v4"
)

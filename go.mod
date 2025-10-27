module example.com/repo1-with-vulnerable-releases

go 1.25.1

require (
	github.com/gin-gonic/gin v1.8.1
	github.com/golang-jwt/jwt/v4 v4.5.2
	github.com/gorilla/websocket v1.4.0
	golang.org/x/crypto v0.36.0
	golang.org/x/net v0.37.0
	golang.org/x/text v0.23.0
)

replace github.com/gorilla/websocket => github.com/gorilla/websocket v1.4.0

replace golang.org/x/net => golang.org/x/net v0.37.0

replace golang.org/x/crypto => golang.org/x/crypto v0.34.0

replace github.com/gin-gonic/gin => github.com/gin-gonic/gin v1.8.1

replace github.com/golang-jwt/jwt/v4 => github.com/golang-jwt/jwt/v4 v4.5.2

replace golang.org/x/text => golang.org/x/text v0.3.5

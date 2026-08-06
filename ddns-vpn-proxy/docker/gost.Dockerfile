FROM --platform=$BUILDPLATFORM golang:1.26.5-alpine3.24@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS builder

ARG TARGETOS
ARG TARGETARCH

WORKDIR /src

# The archive is the exact upstream commit used for this image. Its checksum
# prevents a mutable branch/tag or an intermediary from changing the source.
ADD --checksum=sha256:f6f52fbe825c00ff7e102f956d0c055527f81606387b33ccfb476acf8e8a88ec \
  https://codeload.github.com/go-gost/gost/tar.gz/5a01aa4fd2085156f1f6138774a9a399dbb92e1a \
  /tmp/gost.tar.gz

ENV GOPROXY=https://proxy.golang.org \
    GOSUMDB=sum.golang.org \
    CGO_ENABLED=0

RUN tar -xzf /tmp/gost.tar.gz --strip-components=1 -C /src \
  && rm /tmp/gost.tar.gz

# These reviewed module files replace the upstream graph. -mod=readonly below
# turns any undeclared dependency change into a build failure.
COPY docker/gost/go.mod docker/gost/go.sum /src/

RUN go mod download \
  && go mod verify \
  && GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go list -mod=readonly -deps ./cmd/gost > /tmp/gost-production-packages \
  && GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go list -mod=readonly -deps -test ./... > /tmp/gost-test-packages \
  && test -s /tmp/gost-production-packages \
  && test -s /tmp/gost-test-packages \
  && ! grep -Eq '^golang\.org/x/crypto/openpgp(/|$)' /tmp/gost-production-packages \
  && ! grep -Eq '^golang\.org/x/crypto/openpgp(/|$)' /tmp/gost-test-packages \
  && test "$(go list -mod=readonly -m -f '{{.Version}}' golang.org/x/text)" = v0.39.0 \
  && test "$(go list -mod=readonly -m -f '{{.Version}}' golang.org/x/net)" = v0.56.0 \
  && test "$(go list -mod=readonly -m -f '{{.Version}}' golang.org/x/crypto)" = v0.53.0 \
  && test "$(go list -mod=readonly -m -f '{{.Version}}' golang.org/x/mod)" = v0.37.0 \
  && test "$(go list -mod=readonly -m -f '{{.Version}}' golang.org/x/tools)" = v0.47.0

RUN GOOS=$TARGETOS GOARCH=$TARGETARCH \
  go build -mod=readonly -trimpath -buildvcs=false -ldflags '-buildid=' -o /out/gost ./cmd/gost

FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

COPY --from=builder --chmod=0555 /out/gost /usr/local/bin/gost
COPY --from=builder --chmod=0444 /src/LICENSE /usr/share/licenses/gost/LICENSE
COPY --chmod=0555 docker/gost-healthcheck.sh /usr/local/bin/gost-healthcheck

LABEL org.opencontainers.image.source="https://github.com/DF-wu/myServices" \
      org.opencontainers.image.title="Hardened GOST SOCKS5 sidecar" \
      org.opencontainers.image.version="3.3.0-5a01aa4-alpine3.24.1" \
      org.opencontainers.image.revision="5a01aa4fd2085156f1f6138774a9a399dbb92e1a" \
      io.df-wu.gost.upstream-source="https://github.com/go-gost/gost" \
      io.df-wu.gost.upstream-revision="5a01aa4fd2085156f1f6138774a9a399dbb92e1a" \
      io.df-wu.gost.source-sha256="f6f52fbe825c00ff7e102f956d0c055527f81606387b33ccfb476acf8e8a88ec" \
      io.df-wu.gost.builder="golang:1.26.5-alpine3.24@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2" \
      io.df-wu.gost.x-text="v0.39.0"

ENV HOME=/tmp \
    GOST_LOGGER_LEVEL=warn

USER 65532:65532
ENTRYPOINT ["/usr/local/bin/gost"]

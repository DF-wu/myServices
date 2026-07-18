ARG BUILDPLATFORM=linux/amd64

FROM --platform=${BUILDPLATFORM} golang:1.25.12-alpine3.23@sha256:cc985ef6f9c3bf9ece7488129c9abe0a150388ccdfa428d886fc709dca0b230a AS source

ARG GLUETUN_SOURCE_SHA=7f22fb32764d5d7548bc669cde88c57fc1a0de83
ADD --checksum=sha256:3c2915cfaa220b7384c00bbcc7d5a60819eacbf4bd2a8a5bfa3efa4965e75918 \
  https://codeload.github.com/passteque/gluetun/tar.gz/7f22fb32764d5d7548bc669cde88c57fc1a0de83 \
  /tmp/gluetun-source.tar.gz

WORKDIR /tmp/gobuild
RUN tar -xzf /tmp/gluetun-source.tar.gz --strip-components=1 && \
    rm /tmp/gluetun-source.tar.gz && \
    test "$(sha256sum internal/alpine/users.go)" = \
      "a24217e6b57cffa907186529469aa107829b71c72513c07abc1a341f8c9e6d90  internal/alpine/users.go" && \
    test "$(sha256sum internal/natpmp/rpc_test.go)" = \
      "c697ad8f1e29ae563212f140afca36350f9d6e61d35eb933389a3637e74945b0  internal/natpmp/rpc_test.go" && \
    sed -i \
      's/initialConnectionDuration: time.Millisecond,/initialConnectionDuration: 100 * time.Millisecond,/' \
      internal/natpmp/rpc_test.go && \
    grep -Fq 'initialConnectionDuration: 100 * time.Millisecond,' internal/natpmp/rpc_test.go

# Upstream returns an empty process user when UID 1000 already has the requested
# name. The read-only runtime must pre-create that user, so preserve the exact
# name and regression-test the branch before compiling the production binary.
# The NAT-PMP call-error test had a 1ms deadline that could expire before its
# local UDP fixture consumed the request; widen that test-only scheduling window.
COPY docker/gluetun/users.go internal/alpine/users.go
COPY docker/gluetun/users_regression_test.go internal/alpine/users_regression_test.go

# These reviewed module files apply only security updates to the exact v3.41.1
# source above. go.sum remains the content-integrity boundary for every module.
COPY docker/gluetun/go.mod docker/gluetun/go.sum ./
RUN go mod download && go mod verify

# GO-2026-5932 is scoped to the deprecated golang.org/x/crypto/openpgp
# packages. Fail closed if one enters the production dependency graph.
RUN go list -deps ./cmd/gluetun > /tmp/gluetun-deps && \
    ! grep -Eq '^golang[.]org/x/crypto/openpgp(/|$)' /tmp/gluetun-deps && \
    rm /tmp/gluetun-deps

FROM source AS test
ENV CGO_ENABLED=0
RUN go test ./...

FROM test AS build
ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG TARGETVARIANT
ARG GLUETUN_VERSION=v3.41.1-patched-20260718
ARG GLUETUN_CREATED=2026-07-18T10:30:00Z
ARG GLUETUN_SOURCE_SHA=7f22fb32764d5d7548bc669cde88c57fc1a0de83
RUN if [ "${TARGETARCH}" = arm ]; then export GOARM="${TARGETVARIANT#v}"; fi && \
    GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
    go build -trimpath -buildvcs=false \
      -ldflags="-s -w \
      -X 'main.version=${GLUETUN_VERSION}' \
      -X 'main.created=${GLUETUN_CREATED}' \
      -X 'main.commit=${GLUETUN_SOURCE_SHA}'" \
      -o /tmp/gluetun-entrypoint ./cmd/gluetun

# The official master runtime supplies the scanned Alpine 3.23.5/OpenVPN 2.6
# userspace. Its vulnerable Go binary is replaced below; legacy OpenVPN 2.5 is
# removed. The final merged image contains only the reviewed v3.41.1 binary.
FROM qmcgaw/gluetun:latest@sha256:b0ee2135e6ba52ad3f102aae9663707cd1c9531485117067a380d3b2b6dd991d

USER root
RUN rm -f /usr/sbin/openvpn2.5 && \
    adduser -D -H -u 1000 -s /sbin/nologin nonrootuser

COPY --from=build --chmod=0555 /tmp/gluetun-entrypoint /gluetun-entrypoint

LABEL org.opencontainers.image.source="https://github.com/DF-wu/myServices" \
      org.opencontainers.image.title="Security-patched Gluetun v3.41.1" \
      org.opencontainers.image.version="v3.41.1-patched-20260718" \
      org.opencontainers.image.revision="7f22fb32764d5d7548bc669cde88c57fc1a0de83" \
      io.df-wu.gluetun.upstream-source="https://github.com/passteque/gluetun" \
      io.df-wu.gluetun.upstream-revision="7f22fb32764d5d7548bc669cde88c57fc1a0de83" \
      io.df-wu.gluetun.patch="return-existing-matching-username"

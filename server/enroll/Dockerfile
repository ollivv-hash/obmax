# obmax-enroll: built on the Pi (arm64) with `docker compose up -d --build`.
FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
COPY web ./web
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /obmax-enroll .

# No shell, no package manager: the binary, CA certificates and a non-root user.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /obmax-enroll /obmax-enroll
USER nonroot:nonroot
VOLUME ["/data"]
EXPOSE 8787 8788
HEALTHCHECK --interval=60s --timeout=5s --retries=3 CMD ["/obmax-enroll", "healthcheck"]
ENTRYPOINT ["/obmax-enroll"]

# Stage 1: build
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o demo-app ./cmd/server

# Stage 2: minimal runtime
FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/demo-app /demo-app
ENTRYPOINT ["/demo-app"]

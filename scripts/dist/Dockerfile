# The published image (ghcr.io/sam-apostel/blitr), made from a release's Linux tarballs by the release
# workflow. The repository's own Dockerfile builds from source instead.
#
#   docker run --rm -v "$PWD:/work" ghcr.io/sam-apostel/blitr render MyView.swift -o shot.png
#
# The base image is the Swift toolchain the release was built with: user sources are compiled at render time.
ARG SWIFT_VERSION
FROM swift:${SWIFT_VERSION}-noble

ARG VERSION
ARG TARGETARCH
COPY assets/ /tmp/assets/
RUN set -eu; \
    case "$TARGETARCH" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) echo "unsupported $TARGETARCH" >&2; exit 1 ;; esac; \
    mkdir -p /opt/blitr; \
    tar -xzf "/tmp/assets/blitr-$VERSION-linux-$arch.tar.gz" -C /opt/blitr --strip-components=1 --no-same-owner; \
    ln -s /opt/blitr/bin/blitr /usr/local/bin/blitr; \
    rm -rf /tmp/assets

LABEL org.opencontainers.image.source="https://github.com/Sam-Apostel/blitr" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.description="Render SwiftUI previews to PNG without a simulator"

# Apple's fonts are not redistributable: mount your own copy and point the tool at it with
#   -v /path/to/apple-fonts:/fonts -e BLITR_FONTS=/fonts
WORKDIR /work
ENTRYPOINT ["blitr"]

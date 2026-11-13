# swiftui-screenshot in a container: SwiftUI source in, PNG out.
#
#   docker build -t swiftui-screenshot .
#   docker run --rm -v "$PWD:/work" swiftui-screenshot render MyView.swift -o shot.png
#
# The image keeps the Swift toolchain because user sources are compiled at render time.
FROM swift:6.4.2-noble

RUN apt-get update \
 && apt-get install -y --no-install-recommends libharfbuzz-dev curl unzip binutils ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/swiftui-screenshot
COPY . .

# Pinned Skia + open fonts, then an optimized build of the module and the tool.
RUN scripts/bootstrap.sh \
 && swift build -c release \
 && ln -s "$(swift build -c release --show-bin-path)/swiftui-screenshot" /usr/local/bin/swiftui-screenshot \
 && swiftui-screenshot doctor

# To use your own copy of SF Pro (not redistributable), mount it and point the tool at it:
#   -v /path/to/apple-fonts:/fonts -e SWIFTUI_SCREENSHOT_FONTS=/fonts
WORKDIR /work
ENTRYPOINT ["swiftui-screenshot"]

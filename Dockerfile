FROM frolvlad/alpine-glibc
LABEL maintainer "Alexander Groß <agross@therightstuff.de>"

COPY ./docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["hub", "run"]

EXPOSE 8080

WORKDIR /hub

HEALTHCHECK --start-period=1m \
            CMD wget --server-response --output-document=/dev/null http://localhost:8080 || exit 1

ARG VERSION=2019.1.11960
ARG DOWNLOAD_URL=https://download.jetbrains.com/hub/hub-$VERSION.zip
ARG SHA_DOWNLOAD_URL=https://download.jetbrains.com/hub/hub-$VERSION.zip.sha256

RUN echo Creating hub user and group with static ID of 4000 && \
    addgroup -g 4000 -S hub && \
    adduser -g "JetBrains Hub" -S -h "$(pwd)" -u 4000 -G hub hub && \
    \
    echo Installing packages && \
    apk add --update bash \
                     ca-certificates \
                     coreutils \
                     wget && \
    \
    echo Downloading $DOWNLOAD_URL to $(pwd) && \
    wget --progress bar:force:noscroll \
         "$DOWNLOAD_URL" && \
    \
    echo Verifying download && \
    wget --progress bar:force:noscroll \
         --output-document \
         download.sha256 \
         "$SHA_DOWNLOAD_URL" && \
    \
    sha256sum -c download.sha256 && \
    rm download.sha256 && \
    \
    echo Extracting to $(pwd) && \
    unzip ./hub-$VERSION.zip \
          -d . \
          -x hub-$VERSION/internal/java/linux-amd64/man/* \
             hub-$VERSION/internal/java/windows-amd64/* \
             hub-$VERSION/internal/java/mac-x64/* && \
    rm hub-$VERSION.zip && \
    mv hub-$VERSION/* . && \
    rm -r hub-$VERSION && \
    \
    chown -R hub:hub . && \
    chmod +x /docker-entrypoint.sh

USER hub

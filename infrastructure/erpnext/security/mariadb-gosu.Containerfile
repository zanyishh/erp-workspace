# Same MariaDB engine and entrypoint, with the maintained gosu helper rebuilt
# using the pinned patched Go compiler. This does not upgrade shared databases.
FROM mariadb@sha256:d36f18d65a0459510b8b0f643b226a6d299e3206486e2b64ff20754a6d291707
COPY artifacts/gosu-linux-arm64 /usr/local/bin/gosu
COPY artifacts/gosu-LICENSE /usr/share/doc/gosu/LICENSE

# Reuse the OSS project's locked Playwright, Chromium, requests and pypdf.
FROM node:22.16.0-bookworm-slim@sha256:1471ea646673136b8308550ac14b36d847ffb21c24bc31828279e443c924e488 AS uploader
WORKDIR /opt/uploader
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --omit=dev --no-audit --no-fund

FROM ghcr.io/jwoglom/remarkable-substack/remarkable-substack:v0.3.9@sha256:3111cc496453c105136adb8f67e9afcfdb2c996e62559ab3ee3e99463f35d11b
USER root
COPY --from=uploader /usr/local/bin/node /usr/local/bin/node
COPY --from=uploader /opt/uploader /opt/uploader
RUN ln -s /opt/uploader/node_modules/.bin/rmapi-js /usr/local/bin/rmapi-js && rmapi-js --version
COPY digest.py /app/digest.py
ENV RMAPI_CONFIG_DIR=/data/rmapi NO_COLOR=1 PYTHONDONTWRITEBYTECODE=1
USER 1000:100
ENTRYPOINT ["python3", "-u", "/app/digest.py"]
CMD ["--config", "/config/config.json"]

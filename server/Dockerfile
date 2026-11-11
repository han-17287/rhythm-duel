# Keep Render Root Directory = server. Fetch the matching public game source.
FROM python:3.12-slim-bookworm AS web-build
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libfontconfig1 libx11-6 libxcursor1 libxinerama1 \
    libxrandr2 libxi6 libgl1 libasound2 libpulse0 libudev1 \
    && rm -rf /var/lib/apt/lists/*
# Bump this revision for client-only releases under Render rootDir=server.
ARG CLIENT_REVISION=double-beat-ui-v2
ADD https://codeload.github.com/han-17287/rhythm-duel/zip/refs/heads/main?revision=${CLIENT_REVISION} /tmp/game.zip
RUN python -m zipfile -e /tmp/game.zip /src
WORKDIR /src/rhythm-duel-main
RUN python tools/build_web.py

FROM python:3.12-slim-bookworm
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY server.py accounts.py scoring.py assets.py ./
COPY --from=web-build /src/rhythm-duel-main/build/web ./static
RUN chmod a+r /app/*.py /app/requirements.txt && chmod -R a+rX /app/static
USER 65534:65534
EXPOSE 8765
CMD ["python", "-u", "server.py"]

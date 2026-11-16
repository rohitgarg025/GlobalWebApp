# LibreDWG (dwg2dxf) for the Quantity Takeoff module, built from the GNU release
FROM python:3.11-slim AS libredwg
ARG LIBREDWG_VERSION=0.13.3
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates xz-utils texinfo \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://ftp.gnu.org/gnu/libredwg/libredwg-${LIBREDWG_VERSION}.tar.xz" | tar -xJ \
 && cd "libredwg-${LIBREDWG_VERSION}" \
 && ./configure --prefix=/opt/libredwg --disable-bindings --disable-static \
 && make -j"$(nproc)" \
 && make install

FROM python:3.11-slim
COPY --from=libredwg /opt/libredwg /opt/libredwg
ENV PATH="/opt/libredwg/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/libredwg/lib"
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD python -c "import os,urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"8000\")}/api/health', timeout=4)"
CMD uvicorn app.main_api:app --host 0.0.0.0 --port ${PORT:-8000}

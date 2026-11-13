# ---- Версии ----
ARG PG_VERSION=18.7
ARG PGVECTOR_VERSION=0.8.7

# ---- Этап 1: сборка pgvector ----
FROM postgres:${PG_VERSION}-alpine AS builder
ARG PGVECTOR_VERSION

RUN apk add --no-cache git build-base

RUN git clone --depth 1 --branch v${PGVECTOR_VERSION} \
        https://github.com/pgvector/pgvector.git /src

WORKDIR /src
# OPTFLAGS="" убирает -march=native: иначе vector.so привязан к CPU машины сборки.
# with_llvm=no: clang для JIT-биткода в сборщике нет, а без него pgvector работает так же
RUN make OPTFLAGS="" with_llvm=no \
  && make install DESTDIR=/out with_llvm=no

# ---- Этап 2: итоговый образ ----
FROM postgres:${PG_VERSION}-alpine

COPY --from=builder /out/usr/local/ /usr/local/

# По TCP, а не через сокет: при первом старте init-скрипты идут на временном сервере без TCP,
# и контейнер не станет healthy раньше времени
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
  CMD pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-${POSTGRES_USER:-postgres}}" || exit 1

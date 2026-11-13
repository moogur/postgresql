# Докер образ PostgreSQL с pgvector

Официальный образ `postgres:<версия>-alpine` с собранным расширением
[pgvector](https://github.com/pgvector/pgvector) — тип `vector` и индексы HNSW/IVFFlat для поиска
по эмбеддингам. Всё остальное — entrypoint, переменные окружения, init-скрипты — как в
[официальном образе](https://hub.docker.com/_/postgres).

pgvector собирается в отдельном этапе и копируется в итоговый образ: компилятора и git в нём нет.

## Версии

Задаются в [`Dockerfile`](Dockerfile) через `ARG`:

| `ARG` | Что задаёт |
| --- | --- |
| `PG_VERSION` | Тег `postgres:<PG_VERSION>-alpine` ([теги](https://hub.docker.com/_/postgres/tags)) |
| `PGVECTOR_VERSION` | Тег pgvector без `v` ([релизы](https://github.com/pgvector/pgvector/tags)) |

После подъёма `PGVECTOR_VERSION` расширение в уже существующих базах обновляется вручную, в каждой
базе, где оно включено:

```sql
ALTER EXTENSION vector UPDATE;
```

Минорная версия PostgreSQL (`18.7` → `18.8`) поднимается заменой образа. Мажорная (`18` → `19`) —
нет: данные нужно перенести через `pg_dump`/`pg_restore` или `pg_upgrade`, новый сервер старый
каталог данных не откроет.

## Запуск

Переменные окружения — из официального образа, основные:

| Переменная | Что задаёт |
| --- | --- |
| `POSTGRES_PASSWORD` | Пароль суперпользователя. Обязательна при первом старте |
| `POSTGRES_USER` | Имя суперпользователя (необяз., по умолчанию `postgres`) |
| `POSTGRES_DB` | База, создаваемая при первом старте (необяз., по умолчанию как `POSTGRES_USER`) |

Данные лежат в `/var/lib/postgresql` — туда монтируется volume. С PostgreSQL 18 сам каталог
данных — `/var/lib/postgresql/18/docker`, поэтому монтировать нужно именно `/var/lib/postgresql`,
а не `/var/lib/postgresql/data`, как для старых версий.

```bash
docker run -d --name postgres \
  -e POSTGRES_PASSWORD=<пароль> \
  -v pgdata:/var/lib/postgresql \
  -p 5432:5432 \
  docker.pkg.github.com/moogur/postgresql/postgresql:v1
```

Переменные `POSTGRES_*` читаются только при инициализации пустого каталога данных: на существующих
данных их смена пароль и пользователя не меняет.

pgvector включается в каждой базе отдельно:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

Чтобы сделать это при первом старте, положить `.sql` с этой командой в
`/docker-entrypoint-initdb.d/` — его выполнит entrypoint официального образа.

Healthcheck встроен в образ: `pg_isready` по TCP на `127.0.0.1`. Пока при первом старте работают
init-скрипты, сервер слушает только сокет, поэтому контейнер становится `healthy` лишь после
полной инициализации.

## Образ

Публикуется в GitHub Packages:

```text
docker.pkg.github.com/moogur/postgresql/postgresql:<тег>
```

| Тег | Что означает |
| --- | --- |
| `v1.1.1` | Конкретный релиз, никогда не меняется |
| `v1.1` | Последний патч минорной версии |
| `v1` | Последний релиз мажорной версии |
| `latest` | Последний релиз вообще |

Теги образа — версии этого репозитория, а не PostgreSQL: какая версия PostgreSQL и pgvector внутри,
видно в `Dockerfile` на соответствующем git-теге.

## Релиз

Сборка и публикация образа идут по пушу git-тега формата `vX.Y.Z`
([`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)):

```bash
git tag v1.0.0
git push origin v1.0.0
```

Workflow вызывает `deploy_for_docker_container` из
[all-workflows](https://github.com/moogur/all-workflows), он раскладывает тег в `v1.0.0`, `v1.0`,
`v1`, `latest`. Задачи Kaneo из коммитов между двумя последними тегами уходят в `done` с версией.
Пуш в `master` образ не собирает, только переводит задачу в `in-progress`
([`.github/workflows/push.yml`](.github/workflows/push.yml)). Нужны секреты `KANEO_HOST`, `KANEO_TOKEN`.

## Разработка

```bash
npm install                          # husky и git-хуки
docker build -t postgresql:local .   # локальная сборка
```

Сообщения коммитов проверяет хук [`.husky/commit-msg`](.husky/commit-msg), валидируется только заголовок:

```text
[DOC-<номер>] <type>(<scope>): <subject>
```

Допустимые `type`: `feature`, `bugfix`, `ci`, `config`, `refactor`, `test`, `docs`; `scope` и
`subject` — нижний регистр, `subject` не длиннее 125 символов.

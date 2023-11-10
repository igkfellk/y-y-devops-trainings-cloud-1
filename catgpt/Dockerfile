# Используем образ Golang рекомендуемый в задании
FROM golang:1.21 AS builder

# Указываем автора файла
MAINTAINER Igor Kucherenko <i.kucherenko@test.ru>

# Устанавливаем и переходим в рабочую директорию
WORKDIR /go/src/app

# Копируем go.mod и go.sum для загрузки зависимостей
COPY go.mod go.sum ./

# Загружаем зависимости
RUN go mod download

# Копируем исходный код приложения
COPY . .

# Собираем приложение
RUN CGO_ENABLED=0 go build -o /go/bin/app
RUN chmod +x /go/bin/app

# Создаем runtime образ на основе gcr.io/distroless/static-debian12:latest-amd64
FROM gcr.io/distroless/static-debian12:latest-amd64

# Копируем собранный бинарный файл из builder образа
COPY --from=builder /go/bin/app /go/bin/app

# Определяем команду, которая будет запускаться при запуске контейнера
CMD ["/go/bin/app"]

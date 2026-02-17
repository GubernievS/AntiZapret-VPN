# Брендирование / Branding

## Кастомизация логотипа

Вы можете заменить дефолтный логотип на свой собственный.

### Файлы для замены:

1. **logo.svg** - Основной логотип (используется на странице входа и в header)
   - Рекомендуемый размер: 200x60px
   - Формат: SVG, PNG

2. **favicon.svg** - Иконка сайта (отображается во вкладке браузера)
   - Рекомендуемый размер: 32x32px
   - Формат: SVG, PNG, ICO

### Как заменить логотип:

#### Вариант 1: Замена файлов напрямую (production)

```bash
# Для прямой установки
sudo cp your-logo.svg /opt/corpweb/frontend/branding/logo.svg
sudo cp your-favicon.svg /opt/corpweb/frontend/branding/favicon.svg

# Для Docker
docker cp your-logo.svg corpweb-nginx:/usr/share/nginx/html/branding/logo.svg
docker cp your-favicon.svg corpweb-nginx:/usr/share/nginx/html/branding/favicon.svg
```

#### Вариант 2: Замена перед сборкой (development)

Замените файлы в `frontend/public/branding/` перед запуском:

```bash
cp your-logo.svg frontend/public/branding/logo.svg
cp your-favicon.svg frontend/public/branding/favicon.svg
npm run build
```

### Кастомизация названия компании

Отредактируйте файл `.env`:

```bash
COMPANY_NAME=Ваша Компания
```

После изменения перезапустите сервисы.

## Расположение логотипа в UI

- **Страница входа**: Логотип отображается сверху по центру
- **Header**: Логотип в левом верхнем углу (после входа)
- **Favicon**: Иконка во вкладке браузера

## Поддерживаемые форматы

- SVG (рекомендуется) - масштабируется без потери качества
- PNG - статичное изображение
- JPG - для фотографий (не рекомендуется для логотипов)

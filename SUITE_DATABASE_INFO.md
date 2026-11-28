# DrJaw — складская БД MSSQL (Suite / Dr. Jewelry)

> **Доступ только на чтение.** Использовать **исключительно** во внешнем sync-скрипте (Node.js/Python) на сервере.  
> **Запрещено** подключать эти параметры из Flutter-клиента (см. `.cursorrules`).

## Параметры подключения

| Параметр | Значение |
|----------|----------|
| **Server** | `211.176.43.226,1433` |
| **Database** | `DrJaw` |
| **UserId** | `DrJ_Reader` |
| **Password** | `Read_only11!` |
| **TrustServerCertificate** | `True` |

### Пример строки подключения (ADO.NET / sqlcmd)

```
Server=211.176.43.226,1433;Database=DrJaw;User Id=DrJ_Reader;Password=Read_only11!;TrustServerCertificate=True;
```

---

## Таблица `Articuls` (справочник / модель изделия)

| Поле | Назначение (логика витрины) |
|------|-----------------------------|
| **Id** | Первичный ключ записи справочника |
| **Articul** | Код артикула (связь с экземплярами в `Items`) |
| **Weight** | Масса |
| **Size** | Размер (если задан на уровне модели) |
| **Price** | Базовая / справочная цена |
| **Stones** | Вставки / камни |
| **Status** | Статус в справочнике |
| **Type** | Тип изделия (кольцо, серьги, …) |
| **Metall** | Металл |

---

## Таблица `dbo.Cart` (чек / операция кассы)

Колонки с исторической опечаткой **`Purshase*`** (не `Purchase*`).

| Поле | Назначение |
|------|------------|
| **CartId** | Идентификатор чека (timestamp + суффикс магазина, напр. `20261118112129Основной магазин`) |
| **TotalSum** | Сумма чека (decimal) |
| **PurshaseSource** | Продавец или канал (имя сотрудника, «Оля», «Магазин», …) → **`sales_history.seller_name`** при ETL |
| **PurshaseType** | Способ оплаты: `Наличные` \| `Карта` \| `Перевод` → **`sales_history.payment_method`**: `cash` \| `card` \| `transfer` (как POS PWA) |
| **PurshaseDate** | Дата/время операции |
| **OperationType** | `Sold` \| `Lom` \| `Return` \| `LomOut` — для розницы брать только **`Sold`** |
| **HasLom** | Лом в чеке |

Связь: **`Items.CartId = Cart.CartId`**. Для обогащения истории продаж:  
`INNER JOIN dbo.Cart c ON c.CartId = i.CartId AND c.OperationType = N'Sold' AND i.Status = N'Sold'`.

---

## Таблица `dbo.IUsers` (имена продавцов POS)

| Поле | Назначение |
|------|------------|
| **Name** | Имя продавца (справочник; FK в `Cart` нет) |

Часть значений **`Cart.PurshaseSource`** совпадает с `IUsers.Name`; также встречаются «Оля», «Магазин», «Фейсбук», «Инстаграмм».

---

## Таблица `dbo.Managers` (производитель / бренд)

Справочник **`Items.Manager`** — **не** продавец. В Supabase отчёт: поле **`manufacturer`** из payload / `Manager`, не `seller_name`.

---

## Таблица `Items` (складской экземпляр, уникальный SKU)

| Поле | Назначение (логика витрины) |
|------|-----------------------------|
| **Id** | Первичный ключ экземпляра |
| **Articul** | **Уникальный артикул экземпляра** → ключ синхронизации с `products.sku` в Supabase |
| **Weight** | Масса экземпляра |
| **Size** | Размер |
| **Price** | Цена продажи → `products.sale_price` (KRW, int) |
| **Stones** | Вставки |
| **Status** | Складской статус (напр. «В наличии» / `Sold`) → видимость / `products.status` |
| **Mart** | Магазин → `sales_history.store_location` (ICN/ANS) |
| **Manager** | Производитель → `manufacturer` в отчёте, не `seller_name` |
| **CartId** | Чек продажи → join с `dbo.Cart` |
| **Bonus** | Скидка % |
| **Comment** | Комментарий |

Поля **Type** / **Metall** на экземпляре чаще из join с **`Articuls`**.

---

## Маппинг `PurshaseType` → PWA `payment_method`

| DrJaw `Cart.PurshaseType` | Supabase `sales_history.payment_method` | UI (AdminPosPaymentMethods) |
|---------------------------|----------------------------------------|-----------------------------|
| Наличные | `cash` | Наличные |
| Карта | `card` | Карта |
| Перевод | `transfer` | Перевод |

Скрипт: `migration/enrich_sales_from_mssql.py` (только `legacy_id` **не** `pwa_id_%`).

---

## Связь с Supabase (кратко)

```
[MSSQL DrJaw Items/Articuls] → [sync-скрипт, service_role] → [Supabase public.products]
```

Детальный маппинг — в `.cursorrules`, секция «Маппинг DrJaw → Supabase».

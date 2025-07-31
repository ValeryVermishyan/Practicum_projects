/* Анализ данных для агентства недвижимости
 * 
 * Автор: Вермишян Валерий
 * Дата: 03.04.2025
*/

-- Фильтруем данные от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);

-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?
-- Выведем объявления без выбросов:
dataset AS (SELECT 
	--Категоризировали базу по СПБ и городам ЛО
	flats.id AS id
	,CASE
       WHEN city = 'Санкт-Петербург'
            THEN '1. Санкт-Петербург'
       ELSE '2. Города ЛО'
    END AS region_category
    ,CASE
       WHEN days_exposition <= 30
            THEN '1. До месяца'
       WHEN days_exposition <= 90
            THEN '2. До 3 месяцев'
       WHEN days_exposition <= 180
            THEN '3. До полугода'
       ELSE '4. Более полугода'
    END AS days_exposition_category
	,last_price/total_area AS price_per_metr
	,total_area
	,rooms
	,COALESCE(balcony,0) AS balcony
	,floor
	,ceiling_height
	,floors_total
	,living_area
	,is_apartment
FROM real_estate.flats
LEFT JOIN real_estate.city USING(city_id)
LEFT JOIN real_estate.type USING(type_id)
LEFT JOIN real_estate.advertisement USING(id)
WHERE id IN (SELECT * FROM filtered_id)
	-- Оставим только города
	AND type = 'город'
	-- Оставим только проданные объявления, 
	AND days_exposition IS NOT NULL),
dataset_2 AS (SELECT
	region_category 
	,days_exposition_category
	,count(id) AS adds
	,ROUND(AVG(price_per_metr)::NUMERIC,0) AS avg_price_per_metr
	,ROUND(AVG(total_area)::NUMERIC,1) AS avg_tota_area
	,ROUND(AVG(ceiling_height)::NUMERIC,1) AS avg_ceiling_height
	,ROUND(AVG(floors_total)::NUMERIC,1) AS avg_floors_total
	,ROUND(AVG(living_area)::NUMERIC,1) AS avg_living_area
	,sum(is_apartment) AS sum_is_apartment
	,PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS mediana_rooms
	,PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS mediana_balcony
	,PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floor) AS mediana_floor
FROM dataset
	GROUP BY region_category, days_exposition_category)
SELECT
	region_category
	,days_exposition_category
	,adds
	--посчитали долю категории для каждого региона
	,ROUND((adds/sum(adds) over(PARTITION BY region_category))*100::NUMERIC,1) AS percent_adds
	,avg_price_per_metr
	,avg_tota_area
	,avg_living_area
	,avg_ceiling_height
	,avg_floors_total
	,sum_is_apartment
	,mediana_rooms
	,mediana_balcony
	,mediana_floor
FROM dataset_2

-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?
-- Выведем объявления без выбросов:
activity_adds AS (SELECT
	id
	,first_day_exposition
	,EXTRACT(MONTH FROM first_day_exposition) AS month_start
	,(first_day_exposition + (INTERVAL '1' DAY)*days_exposition)::date AS last_day_exposition
	,EXTRACT(MONTH FROM (first_day_exposition + (INTERVAL '1' DAY)*days_exposition)::date) AS month_stop
	,total_area
	,last_price/total_area AS price_per_metr
	,days_exposition
FROM real_estate.flats
LEFT JOIN real_estate.city USING(city_id)
LEFT JOIN real_estate.type USING(type_id)
FULL JOIN real_estate.advertisement USING(id)
WHERE id IN (SELECT * FROM filtered_id)
	AND first_day_exposition > '2014-12-31'
	AND first_day_exposition < '2019-01-01'
	-- Оставим только города
	AND type = 'город'),
-- Сгруппируем по месяцам кол-во публикаций
count_start AS (SELECT 
	month_start AS MONTH
	,count(id) AS count_start
	,ROUND(AVG(total_area)::NUMERIC,1) AS avg_total_area_start
	,ROUND(AVG(price_per_metr)::NUMERIC,0) AS avg_price_per_metr_start
FROM activity_adds
GROUP BY month_start),
-- Сгруппируем по месяцам кол-во снятий
count_stop AS (SELECT 
	month_stop AS MONTH
	,count(id) AS count_stop
	,ROUND(AVG(total_area)::NUMERIC,1) AS avg_total_area_stop
	,ROUND(AVG(price_per_metr)::NUMERIC,0) AS avg_price_per_metr_stop
FROM activity_adds
WHERE days_exposition IS NOT NULL
GROUP BY month_stop)
SELECT
	MONTH
	,count_start
	,rank() over(ORDER BY count_start desc) count_start_top
	,avg_total_area_start
	,rank() over(ORDER BY avg_total_area_start desc) avg_total_area_start_top
	,avg_price_per_metr_start
	,rank() over(ORDER BY avg_price_per_metr_start desc) avg_price_per_metr_start_top
	,count_stop
	,rank() over(ORDER BY count_stop desc) count_stop_top
	,avg_total_area_stop
	,rank() over(ORDER BY avg_total_area_stop desc) avg_total_area_stop_top
	,avg_price_per_metr_stop
	,rank() over(ORDER BY avg_price_per_metr_stop desc) avg_price_per_metr_stop_top
FROM count_start
LEFT JOIN count_stop USING (month)
ORDER BY MONTH asc 

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.
-- Выведем объявления без выбросов
-- Оставим только объявления лен области и сгруппируем по населенным пунктам
len_obl AS(SELECT
	city
	,count(*) AS total_adds
	,count(days_exposition) AS sold_adds
	,round(count(days_exposition)/count(*)::NUMERIC*100,1) AS percent_sold
	,ROUND(AVG(last_price/total_area)::NUMERIC,0) AS price_per_metr
	,ROUND(AVG(total_area)::NUMERIC,1) AS avg_total_area
	,PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS rooms_mediana
	,PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY COALESCE(balcony,0)) AS balcony_mediana
	,ROUND(AVG(days_exposition)::numeric,0) AS avg_days_exposition
FROM real_estate.flats
LEFT JOIN real_estate.city USING(city_id)
LEFT JOIN real_estate.type USING(type_id)
LEFT JOIN real_estate.advertisement USING(id)
WHERE id IN (SELECT * FROM filtered_id)
--отсекаем СПБ
AND city <> 'Санкт-Петербург'
GROUP BY city
ORDER BY total_adds DESC
LIMIT 12
)
--Здесь проводил ранжирование для нужных полей с помощью оконных функций, чтобы ответить на все вопросы 3 задачи
SELECT
*
FROM len_obl
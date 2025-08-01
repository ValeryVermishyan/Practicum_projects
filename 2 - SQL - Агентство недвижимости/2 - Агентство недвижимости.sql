-- Отфильтруем выбросы
-- Определим аномальные значения (выбросы) по значению перцентилей:
with limits as (
select
	percentile_disc(0.99) within group (order by total_area) as total_area_limit
	,percentile_disc(0.99) within group (order by rooms) as rooms_limit
	,percentile_disc(0.99) within group (order by balcony) as balcony_limit
	,percentile_disc(0.99) within group (order by ceiling_height) as ceiling_height_limit_h
	,percentile_disc(0.01) within group (order by ceiling_height) as ceiling_height_limit_l
from real_estate.flats),
-- Найдем объявления, которые не содержат выбросы
filtered_id as (
select
	id
from real_estate.flats
where total_area < (select total_area_limit from limits)
	and rooms < (select rooms_limit from limits)
	and balcony < (select balcony_limit from limits)
	and ((ceiling_height < (select ceiling_height_limit_h from limits)
            and ceiling_height > (select ceiling_height_limit_l from limits)) or ceiling_height is null));

-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

--Категоризируем базу по региону и по дням активности объявлений
categorized_id as (
select 
	flats.id as id
	,case
		when city = 'Санкт-Петербург'
			then '1. Санкт-Петербург'
		else '2. Города ЛО'
	end as region_category
	,case
		when days_exposition <= 30
			then '1. До месяца'
		when days_exposition <= 90
			then '2. До 3 месяцев'
		when days_exposition <= 180
			then '3. До полугода'
		else '4. Более полугода'
	end as days_exposition_category
	,last_price/total_area as price_per_metr
	,total_area
	,rooms
	,coalesce(balcony,0) as balcony
	,floor
	,ceiling_height
	,floors_total
	,living_area
	,is_apartment
from real_estate.flats
left join real_estate.city using(city_id)
left join real_estate.type using(type_id)
left join real_estate.advertisement using(id)
where id in (select * from filtered_id)
	-- Оставим только города и только проданные объявления
	and type = 'город'
	and days_exposition is not null),
--Сгруппируем и посчитаем статистические данные
grouped_id as (select
	region_category 
	,days_exposition_category
	,count(id) as ads
	--Считаем долю объявлений в каждой категории для каждого региона
	,round((count(id) / sum(count(id)) over (partition by region_category)) * 100::numeric, 1) as percent_adds
	,round(avg(price_per_metr)::numeric,0) as avg_price_per_metr
	,round(avg(total_area)::numeric,1) as avg_total_area
	,round(avg(ceiling_height)::numeric,2) as avg_ceiling_height
	,round(avg(floors_total)::numeric,1) as avg_floors_total
	,round(avg(living_area)::numeric,1) as avg_living_area
	,sum(is_apartment) as total_apartments
	,percentile_disc(0.5) within group (order by rooms) as mediana_rooms
	,percentile_disc(0.5) within group (order by balcony) as mediana_balcony
	,percentile_disc(0.5) within group (order by floor) as mediana_floor
from categorized_id
	ggroup by region_category, days_exposition_category)
select * from grouped_id

-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

-- Выделим месяцы, когда объявление было выложено и когда снято
activity_adds as (
select
	id
	,first_day_exposition
	,(first_day_exposition + (interval '1' day)*days_exposition)::date as last_day_exposition
	,extract(month from first_day_exposition) as month_start
	,extract(month from (first_day_exposition + (interval '1' day)*days_exposition)::date) as month_stop
	,total_area
	,last_price/total_area AS price_per_metr
	,days_exposition
from real_estate.flats
left join real_estate.city using(city_id)
left join real_estate.type using(type_id)
full join real_estate.advertisement using(id)
where id in (select * from filtered_id)
	-- Оставляем объявления с 2015 по 2018 год, так как за остальной период данные неполные
	and first_day_exposition between '2015-01-01' and '2018-12-31'
	-- Оставим только города
	and type = 'город'),
-- Сгруппируем по месяцам кол-во публикаций
count_start as (
select
	month_start as MONTH
	,count(id) as count_start
	,round(avg(total_area)::numeric,1) as avg_total_area_start
	,round(avg(price_per_metr)::numeric,1) as avg_price_per_metr_start
from activity_adds
group by month_start),
-- Сгруппируем по месяцам кол-во снятий
count_stop as (
select
	month_stop as MONTH
	,count(id) as count_stop
	,round(avg(total_area)::numeric,1) as avg_total_area_stop
	,round(avg(price_per_metr)::numeric,1) as avg_price_per_metr_stop
from activity_adds
-- Убираем объявления, которые еще не были сняты с продажи
where days_exposition is not null
group by month_stop)
-- Посчитаем статистические данные
select
	month
	,count_start
	,rank() over(order by count_start desc) count_start_top
	,avg_total_area_start
	,rank() over(order by avg_total_area_start desc) avg_total_area_start_top
	,avg_price_per_metr_start
	,rank() over(order by avg_price_per_metr_start desc) avg_price_per_metr_start_top
	,count_stop
	,rank() over(order by count_stop desc) count_stop_top
	,avg_total_area_stop
	,rank() over(order by avg_total_area_stop desc) avg_total_area_stop_top
	,avg_price_per_metr_stop
	,rank() over(order by avg_price_per_metr_stop desc) avg_price_per_metr_stop_top
from count_start
left join count_stop using(month)
order by month asc

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.
-- Оставим только объявления лен области и сгруппируем по населенным пунктам
select
	city
	,count(*) as total_ads
	--если значение не null, значит объявления продано
	,count(days_exposition) as sold_adds
	,round(count(days_exposition)/count(*)::numeric*100,1) as per_sold
	,round(avg(last_price/total_area)::numeric,0) as price_per_metr
	,round(avg(total_area)::numeric,1) as avg_total_area
	,percentile_disc(0.5) within group (order by rooms) as rooms_mediana
	,percentile_disc(0.5) within group (order by coalesce(balcony,0)) as balcony_mediana
	,round(avg(days_exposition)::numeric,0) as avg_days_exposition
from real_estate.flats
left join real_estate.city using(city_id)
left join real_estate.type using(type_id)
left join real_estate.advertisement using(id)
where id in (select * from filtered_id)
--отсекаем СПБ
and city <> 'Санкт-Петербург'
group by city
order by total_ads desc
limit 12
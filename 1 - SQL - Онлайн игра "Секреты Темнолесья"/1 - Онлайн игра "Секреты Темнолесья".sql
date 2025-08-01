-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
select 
	count(*) as total_users
	,sum(payer) as payers
	,round(sum(payer)/count(*)::numeric*100,1) as perc_payers
from fantasy.users
-- Доля платящих игроков примерно 17.7%. Большинство игроков не платят

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
select 
	race
	,count(*) as total_users
	,sum(payer) as payers
	,round(sum(payer)/count(*)::numeric*100,1) as perc_payers
from fantasy.users
left join fantasy.race using(race_id)
group by race
order by perc_payers desc
--Среди рас выделяются демоны и хоббиты, как расы с наиболее высокой долей платящих - 18.1% и 19.5%.
--Причем демоны выделяются особо сильно, рекомендую присмотреться к ним отдельно.
--Наименьшая доля платящих у ангелов и эльфов - 17.3% и 17.1%. Их следует изучить.
--Орки, люди и северяне соответствуют среднему значению доли платящих  - 17.6%

-- Задача 2. Исследование внутриигровых покупок

-- 2.1. Статистические показатели по полю amount:
select 
	count(transaction_id) as total_transactions
	,sum(amount) as total_amount
	,min(amount) as min_amount
	,round(max(amount)::numeric) as max_amount
	,round(avg(amount)::numeric,1) as avg_amount
	,percentile_disc(0.5) within group (order by amount) as median_amount
	,round(stddev(amount)::numeric) as std_amount
from fantasy.events
--Есть покупки с нулевой стоимостью. Их нужно проанализировать
--Размах стоимостей очень высокий. Так же как и разница между средней стоимостью и медианой, 
--значит есть есть много очень высоких или очень низких значений стоимости
--стандартное отклонение в несколько раз выше среднего значения, что говорит о наличии 
--крупных правосторонних выбросов

-- 2.2: Аномальные нулевые покупки:
select
	count(*) as total_transactions
	,count(*) filter (where amount = 0) as count_amount_is_null
	,round(count(*) filter (where amount = 0)/count(*)::numeric*100,2) as per_amount_is_null
from fantasy.events
--Есть покупки с нулевой стоимостью, но их доля несущественна среди общего количества. 
--Однако в процессе анализа я заметил, что есть много покупок стоимостью 0.01, 0.02 и тд. их стоит проанализировать тоже

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
--Ищем общее кол-во покупок и суммарную стоимость покупок на игрока
with transactions_per_user AS(
select
	id
	,count(*) as total_transactions
	,sum(amount) as total_amount
from fantasy.events
where amount !=0
group by id),
--Получаем статистику по платящим игрокам
payers as (select 
	'payers' as category_users
	,count(id) as total_users
	--Заменяем null на 0 для корректного подсчета среднего
	,round(avg(coalesce(total_transactions,0))::numeric,1) as avg_total_transactions
	,round(avg(coalesce(total_amount,0))::numeric) as avg_total_amount
from fantasy.users
left join transactions_per_user using(id)
where payer = 1),
--Получаем статистику по неплатящим игрокам
not_payers as (select 
	'not payers' as category_users
	,count(id) as total_users
	--Заменяем null на 0 для корректного подсчета среднего
	,round(avg(coalesce(total_transactions,0))::numeric,1) as avg_total_transactions
	,round(avg(coalesce(total_amount,0))::numeric) as avg_total_amount
from fantasy.users
left join transactions_per_user using(id)
where payer = 0)
--Объединяем таблицы
select * from payers 
union 
select * from not_payers
--Платящие игроки покупают меньше, но на большую сумму. 
--Возможно, купив внутриигровую валюту за реальные деньги, они могут позволить себе делать более 
--крупные или частые покупки. 
--Неплатящие игроки, заработав лепестки, сразу их тратят, возможно, чтобы заработать новые.

-- 2.4: Популярные эпические предметы:
--считаем кол-во продаж для каждого предмета + долю продаж от общего кол-ва
with item_transactions as(
select
	distinct item_code
	,count(transaction_id) over(partition by item_code) as total_transactions
	,round(count(transaction_id) over(partition by item_code) / 
		count(transaction_id) over()::numeric*100,2) as per_total_transactions
from fantasy.events
where amount != 0),
payers_who_pays as(
--считаем % купивших игроков от общего кол-ва игроков для каждого предмета	
select 
	item_code
	,round(count(distinct id) / (select count(*) from fantasy.users)::numeric*100,2) as per_users_who_pays
from fantasy.events
group by item_code)
--объединяем таблицы
select
	game_items
	,total_transactions
	,per_total_transactions
	,per_users_who_pays
from item_transactions
left join payers_who_pays using(item_code)
left join fantasy.items using(item_code)
order by per_users_who_pays desc
--Есть 2 предмета, продажи которых составляют абсолютное большинство среди всех продаж/пользователей - это
--Book of Legends и Bag of Holding.
--Возможно, что Book of Legend нужен для прокачивания навыков (прочитал книгу — повысил какой-то навык), 
--а Bag of Holding расширяет возможности игрока (например, переносить больше предметов)
--Эти предметы являются драйверами для совершения игроками покупок, а следовательно и драйверами 
--роста конверсии в платящие игроки.
--Еще есть несколько предметов средней популярности и большинство почти непопулярны. 

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:

--Определяем игроков, которые совершают внутриигровые покупки
with user_has_transaction as (
select
	id
	,1 as user_has_transaction
	,count(*) as total_transactions
	,sum(amount) as sum_transactions
	,sum(amount)/count(*) as avg_sum_transactions
FROM fantasy.events
WHERE amount != 0
group by id),
--Определяем игроков, которые совершают внутриигровые покупки и являются платящими игроками
user_has_transaction_and_pay as (
select
	id
	,1 as user_has_transaction_and_pay
from fantasy.users
left join user_has_transaction using(id)
where payer = 1 and user_has_transaction = 1)
--Считаем данные для каждой расы
select
	race
	,count(id) as users
	,sum(user_has_transaction) as total_user_has_transaction
	--Считаем долю игроков, которые совершают внутриигровые покупки от всех игроков
	,round(sum(user_has_transaction)/count(id)::numeric*100,1) as per_total_user_has_transaction
	--Считаем долю игроков, которые платят от игроков, которые совершают внутриигровые покупки
	,round(sum(user_has_transaction_and_pay)/sum(user_has_transaction)::numeric*100,1) as per_user_payer_to_user_has_transations
	--Считаем среднее кол-во всех транзакций на 1 игрока
	,round(avg(total_transactions)) as avg_total_transactions_to_user
	--Считаем среднюю сумму 1 транзакции на 1 игрока
	,round(avg(avg_sum_transactions)) as avg_sum_1_transaction_to_user
	--Считаем среднюю сумму транзакций на 1 игрока
	,round(avg(sum_transactions)::numeric) as avg_total_sum_transactions_to_user
from fantasy.users
left join fantasy.race using (race_id)
left join user_has_transaction using(id)
left join user_has_transaction_and_pay using(id)
group by race
order by per_total_user_has_transaction desc
--У демонов самая низкая доля пользователей с покупками всего
--и самая высокая доля покупок за реальный деньги среди всех покупок. Возможно за эту расу сложнее играть.
--У людей среднее кол-во транзакций на игрока больше всего, а средняя сумма транзакций на игрока не высокая
--возможно у этой расы часто покупают дешевые предметы.
--Но еще видно, что средняя стоимость 1 транзакции самая низкая у хоббитов

--Общие выводы и рекомендации:
--Следует провести новый анализ, убрав из статистики предметы с низкой стоимостью, так как они искажают данные.
--Отдельно проанализировать предметы по категориям популярности (самые популярные, средние и 
--менее популярные) и понять, сколько они денег приносят, к каким расам они относятся.
--Изучить игру за демонов и хоббитов, чтобы понять, что приводит к высокому проценту покупок 
--за реальные деньги.

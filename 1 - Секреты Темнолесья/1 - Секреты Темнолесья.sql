/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Вермишян Валерий
 * Дата: 9 марта 2025
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT
	COUNT(id) AS total_users
	,SUM(payer) AS payers
	,ROUND(SUM(payer)/COUNT(id)::NUMERIC,3) AS payers_fraction
FROM fantasy.users
-- Доля платящих игроков примерно 17.7%. Большинство игроков не платят

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT
	race
	,SUM(payer) AS payers
	,COUNT(id) AS total_users
	,ROUND(SUM(payer)/COUNT(id)::NUMERIC,3) AS payers_fraction
FROM fantasy.users
LEFT JOIN fantasy.race USING(race_id)
GROUP BY race
--Среди рас выделяются демоны и хоббиты, как расы с наиболее высокой долей платящих - 18.1% и 19.5%.
--Причем демоны выделяются особо сильно, рекомендую присмотреться к ним отдельно.
--Наименьшая доля платящих у ангелов и эльфов - 17.3% и 17.1%. Их следует изучить.
--Орки, люди и северяне соответствуют среднему значению доли платящих  - 17.6%

-- Задача 2. Исследование внутриигровых покупок

-- 2.1. Статистические показатели по полю amount:
SELECT
	COUNT(transaction_id) AS total_transactions
	,SUM(amount) AS total_amount
	,MIN(amount) AS min_amount
	,ROUND(MAX(amount)::NUMERIC,0) AS max_amount
	,ROUND(AVG(amount)::NUMERIC,0) AS avg_amount
	,ROUND((PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount))::NUMERIC,0) AS median_amount
	,ROUND(STDDEV(amount)::NUMERIC,0) AS stand_dev_amount
FROM fantasy.events
--Есть покупки с нулевой стоимостью. Их нужно проанализировать
--Размах стоимостей очень высокий. Так же как и разница между средней стоимостью и медианой, 
--значит есть есть много очень высоких или очень низких значений стоимости

-- 2.2: Аномальные нулевые покупки:
SELECT
	COUNT(*) AS total_transactions
	,COUNT(*) FILTER (WHERE amount = 0) AS count_amount_is_null
	,COUNT(*) FILTER (WHERE amount = 0)/COUNT(transaction_id)::NUMERIC AS amount_is_null_fraction
FROM fantasy.events
--Есть покупки с нулевой стоимостью, но их доля несущественна среди общего количества. 
--Однако в процессе анализа я заметил, что есть много покупок стоимостью 0.01, 0.02 и тд. их стоит проанализировать тоже
--Еще проверил кол-во уникальных пользователей с покупками всего и с покупками без нулевых.
--получилось 13793 и 13792 соответственно, значит при анализе данных в разрезе пользователей можно пренебречь 
--нулевыми покупками и специально их из базы не убирать

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
--Ищем общее кол-во покупок и суммарную стоимость покупок на игрока
WITH transactions_per_user AS(
SELECT
	id
	,COUNT(*) AS total_transactions
	,SUM(amount) AS sum_amount
FROM fantasy.events
WHERE amount != 0
GROUP BY id),
--Присоединяем данные по покупкам в таблицу пользователей и сразу анализируем группу платящих игроков
payers AS (SELECT
	'payers' AS category_users
	,COUNT(id) AS total_users
	,ROUND(AVG(COALESCE(total_transactions,0))::NUMERIC,0) AS avg_total_transactions
	,ROUND(AVG(COALESCE(sum_amount,0))::NUMERIC,0) AS avg_sum_amount
FROM fantasy.users
LEFT JOIN transactions_per_user USING(id)
WHERE payer = 1),
--Аналогично получаем данные по неплатящим игрокам
not_payers AS (SELECT
	'not_payers' AS category_users
	,COUNT(id) AS total_users
	,ROUND(AVG(COALESCE(total_transactions,0))::NUMERIC,0) AS avg_total_transactions
	,ROUND(AVG(COALESCE(sum_amount,0))::NUMERIC,0) AS avg_sum_amount
FROM fantasy.users
LEFT JOIN transactions_per_user USING(id)
WHERE payer = 0)
--Соединяем обе группы пользователей.
SELECT
	*
FROM payers
UNION
SELECT
	*
FROM not_payers
--Платящие игроки покупают меньше, но на большую сумму. 
--Возможно, купив внутриигровую валюту за реальные деньги, они могут позволить себе делать более 
--крупные или частые покупки. 
--Неплатящие игроки, заработав лепестки, сразу их тратят, возможно, чтобы заработать новые.

-- 2.4: Популярные эпические предметы:
--Пока что JOIN не используем, так как в процессе изучения таблиц выяснил, что 
--названия 'Treasure Map' и 'Cloak of Shadows' принадлежат двум разным id
WITH item_codes AS(SELECT
	item_code
	--Считаем кол-во продаж для каждого предмета + долю продаж от общего кол-ва.
	,COUNT(transaction_id) AS total_transation_per_item
	,COUNT(transaction_id)/(SELECT 
								COUNT(transaction_id) 
							FROM fantasy.events 
							WHERE amount > 0)::NUMERIC AS total_transation_per_item_fraction
	--Подсчет доли купивших игроков от общего кол-ва игроков для каждого предмета						
	,COUNT(DISTINCT id)/(SELECT COUNT(*) FROM fantasy.users)::NUMERIC AS distinct_users_fraction
FROM fantasy.events
WHERE amount > 0
GROUP BY item_code)
--Добавляем JOIN
SELECT 
	game_items
	,total_transation_per_item
	,total_transation_per_item_fraction
	,distinct_users_fraction
FROM item_codes
LEFT JOIN fantasy.items USING(item_code)
ORDER BY distinct_users_fraction DESC
--Есть 2 предмета, продажи которых составляют абсолютное большинство среди всех продаж/пользователей - это
--Book of Legends и Bag of Holding.
--Возможно, что Book of Legend нужен для прокачивания навыков (прочитал книгу — повысил какой-то навык), 
--а Bag of Holding расширяет возможности игрока (например, переносить больше предметов)
--Эти предметы являются драйверами для совершения игроками покупок, а следовательно и драйверами 
--роста конверсии в платящие игроки.
--Еще есть несколько предметов средней популярности и большинство почти непопулярны. 

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:

--Определяем игроков, которые освершают внутриигровые покупки
WITH user_has_transaction AS(SELECT
	id
	,1 AS user_has_transaction
	,COUNT(*) AS total_transactions
	,SUM(amount) AS sum_amount
	,SUM(amount)/COUNT(*) AS avg_amount_1_transaction
FROM fantasy.events
WHERE amount != 0
GROUP BY id),
--Считаем платящих покупателей
user_has_pay_and_transation AS(SELECT
	id
	,1 AS user_has_pay_and_transation
FROM fantasy.users
LEFT JOIN user_has_transaction USING(id)
WHERE payer = 1 AND user_has_transaction = 1)
--Cчитаем данные для каждой расы
SELECT
	race
	,COUNT(id) AS users
	,SUM(user_has_transaction) AS total_user_has_transaction
	,ROUND(SUM(user_has_transaction)/COUNT(id)::NUMERIC,2) AS user_has_transaction_fraction
	--Пересчитал как долю платящих покупателей ко всем покупателям
	,ROUND(SUM(user_has_pay_and_transation)/SUM(user_has_transaction)::NUMERIC,2) AS user_payer_fraction
	--Убрал COALESCE, чтобы подсчитать значения только для покупателей
	,ROUND(AVG(total_transactions)::NUMERIC,0) AS avg_total_transactions
	,ROUND(AVG(avg_amount_1_transaction)::NUMERIC,0) AS avg_amount_1_transaction
	,ROUND(AVG(sum_amount)::NUMERIC,0) AS avg_sum_amount
FROM fantasy.users
LEFT JOIN fantasy.race USING(race_id)
LEFT JOIN user_has_transaction USING(id)
LEFT JOIN user_has_pay_and_transation USING(id)
GROUP BY race
ORDER BY user_has_transaction_fraction DESC
--У демонов самая низкая доля пользователей с покупками всего
--и самая высокая доля покупок за реальный деньги среди всех покупок. Возможно за эту расу сложнее играть
--У людей среднее кол-во транзакций на игрока больше всего, а средняя сумма транзакций на игрока не высокая
--возможно у этой расы часто покупают дешевые предметы.
--Но еще видно, что средняя стоимость 1 транзакции самая низкая у хоббитов

--Общие выводы и рекомендации:
--Следует провести новый анализ, убрав из статистики предметы с низкой стоимостью, так как они искажают данные.
--Отдельно проанализировать предметы по категориям популярности (самые популярные, средние и 
--менее популярные) и понять, сколько они денег приносят, к каким расам они относятся.
--Изучить игру за демонов и хоббитов, чтобы понять, что приводит к высокому проценту покупок 
--за реальные деньги.

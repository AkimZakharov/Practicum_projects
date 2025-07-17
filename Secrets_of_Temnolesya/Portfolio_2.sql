/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Захаров Аким Сергеевич
 * Дата: 15.11.2024
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT
	COUNT(DISTINCT id) AS quant_all_users,
	SUM(payer) AS quant_pay_users,
	ROUND(AVG(payer), 3) AS part_pay_users
FROM
	fantasy.users;
	
-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT
	race,
	COUNT(DISTINCT id) AS quant_users_by_race,
	SUM(payer) AS quant_pay_users,
	ROUND(SUM(payer)/COUNT(DISTINCT id)::NUMERIC, 3) AS part_pay_users_by_race
FROM 
	fantasy.users AS u
JOIN
	fantasy.race AS r
ON 
	u.race_id=r.race_id
GROUP BY
	r.race
ORDER BY
	part_pay_users_by_race DESC;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT
	COUNT(amount) AS quant_purch,
	ROUND(SUM(amount)::NUMERIC,0) AS sum_purch,
	ROUND(MIN(amount)::NUMERIC,0) AS min_purch,
	(SELECT 
		ROUND(MIN(amount)::NUMERIC,2) AS min_purch
	FROM
		fantasy.events
	WHERE
		amount!=0) AS min_purch_not_0,
	ROUND(MAX(amount)::NUMERIC,0) AS max_purch,
	ROUND(AVG(amount)::NUMERIC,0) AS average_purch,
	ROUND((PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount))::NUMERIC,0) AS mediana_purch,
	ROUND(STDDEV(amount)::NUMERIC,0) AS dev_purch
FROM
	fantasy.events;

-- 2.2: Аномальные нулевые покупки:
SELECT
	COUNT(amount) AS quant_purch_0,
	(SELECT 
		COUNT(amount) 
	FROM
		fantasy.events) AS all_quant_purch,
	ROUND(COUNT(amount)/(SELECT COUNT(amount) 
		FROM
			fantasy.events)::NUMERIC, 4) AS part_purch_0
FROM
	fantasy.events
WHERE 
	amount = 0;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
SELECT 
	CASE
		WHEN
			payer=1
		THEN
			'Платящие'
		ELSE
			'Неплатящие'
		END AS payer, 
	COUNT(DISTINCT u.id) AS quant_purch_users, 
	ROUND(COUNT(e.transaction_id) / COUNT(DISTINCT u.id), 0)  AS avg_quant_purch_by_user,
	ROUND(SUM(e.amount)::NUMERIC / COUNT(DISTINCT u.id), 0) AS avg_sum_purch_by_user
FROM
	fantasy.users AS u
LEFT JOIN
	fantasy.events AS e
ON
	e.id=u.id
WHERE
	amount>0
GROUP BY 
	payer;
	
-- 2.4: Популярные эпические предметы:
WITH purch_by_item AS ( 
SELECT 
	i.game_items, 
	COUNT(e.transaction_id) AS quant_purch_by_item, 
	COUNT(DISTINCT e.id) AS users_purch_by_item, 
	SUM(COUNT(e.transaction_id)) OVER () AS sum_purch_items
FROM 
	fantasy.events AS e 
JOIN 
	fantasy.items AS i 
ON 
	e.item_code = i.item_code
WHERE amount!=0
GROUP BY 
	i.game_items) 
SELECT 
	p.game_items, 
	p.quant_purch_by_item, 
	p.quant_purch_by_item / p.sum_purch_items AS popular_purch, 
	ROUND(p.users_purch_by_item / (SELECT COUNT(DISTINCT id)
		FROM 
			fantasy.events)::NUMERIC, 7) AS part_purch_users
FROM 
	purch_by_item AS p 
ORDER BY 
	popular_purch DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
WITH users_by_race AS ( 
SELECT 
	r.race, 
	COUNT(DISTINCT u.id) AS quant_users
FROM 
	fantasy.users AS u 
JOIN 
	fantasy.race AS r 
ON 
	u.race_id = r.race_id 
GROUP BY 
	r.race),	
purch_users_by_race AS ( 
SELECT 
	r.race, 
	COUNT(DISTINCT u.id) AS quant_purch_users
FROM 
	fantasy.users AS u 
JOIN 
	fantasy.events AS e 
ON 
	u.id = e.id 
JOIN 
	fantasy.race AS r
ON 
	u.race_id = r.race_id 
WHERE 
	e.amount > 0 
GROUP BY 
	r.race),	
activ_by_race AS (
SELECT 
r.race, 
COUNT(e.transaction_id) AS quant_purch, 
SUM(e.amount) AS sum_purch 
FROM 
	fantasy.users AS u 
JOIN 
	fantasy.events AS e 
ON 
	u.id = e.id 
JOIN 
	fantasy.race AS r 
ON 
	u.race_id = r.race_id 
WHERE 
	e.amount > 0 
GROUP BY 
	r.race),
pay_users_by_race AS (
SELECT  
	r.race, 
	COUNT(DISTINCT u.id) AS quant_pay_users
FROM 
	fantasy.users AS u 
JOIN 
	fantasy.events AS e 
ON 
	u.id = e.id 
JOIN 
	fantasy.race AS r
ON 
	u.race_id = r.race_id 
WHERE
	u.payer = 1
GROUP BY
	r.race
)
SELECT 
	u.race, 
	u.quant_users, 
	p.quant_purch_users, 
	ROUND(p.quant_purch_users::NUMERIC / u.quant_users, 2) AS part_purch_users, 
	ROUND(pu.quant_pay_users::NUMERIC / p.quant_purch_users, 2) AS part_pay_by_purch_users, 
	ROUND(a.quant_purch::NUMERIC / p.quant_purch_users, 0) AS avg_quant_purch_by_user, 
	ROUND(a.sum_purch::NUMERIC / a.quant_purch,2) AS avg_amount_purch, 
	ROUND(a.sum_purch::NUMERIC / p.quant_purch_users,2) AS avg_amount_purch_by_user 
FROM 
	users_by_race AS u 
JOIN 
	purch_users_by_race AS p 
ON 
	u.race = p.race
JOIN 
	activ_by_race AS a 
ON 
	p.race = a.race
JOIN 
	pay_users_by_race AS pu 
ON
	pu.race = a.race
ORDER BY
	u.race;




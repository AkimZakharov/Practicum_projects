/* Проект: Анализ данных для агентства недвижимости
*/

-- Пример фильтрации данных от аномальных значений
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
        AND rooms < (SELECT rooms_limit FROM limits) 
        AND balcony < (SELECT balcony_limit FROM limits) 
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
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

WITH limits AS ( 
	SELECT 
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit, 
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit, 
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit, 
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h, 
		PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l 
	FROM 
		real_estate.flats), 
filtered_id AS ( 
	SELECT 
		id 
	FROM 
		real_estate.flats 
	WHERE 
		total_area < (SELECT total_area_limit FROM limits) 
	AND rooms < (SELECT rooms_limit FROM limits) 
	AND balcony < (SELECT balcony_limit FROM limits) 
	AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
	AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)), 
category AS ( 
	SELECT 
		a.id,
		f.total_area, 
		f.rooms, 
		f.ceiling_height,
		f.floors_total,
		f.balcony,
	CASE 
		WHEN c.city = 'Санкт-Петербург' 
			THEN 'Санкт-Петербург' 
		ELSE 'ЛенОбл' 
	END AS region, 
	CASE 
		WHEN a.days_exposition is NULL 
			THEN 'без категории' 
		WHEN a.days_exposition BETWEEN 1 AND 30 
			THEN 'месяц' 
		WHEN a.days_exposition BETWEEN 31 AND 90 
			THEN 'квартал' 
		WHEN a.days_exposition BETWEEN 91 AND 180 
			THEN 'полгода' 
		ELSE 'более полугода' 
		END AS activity_period, 
	ROUND(a.last_price::numeric / f.total_area::numeric, 2) AS price_sq_meter 
	FROM 
		real_estate.advertisement AS a 
	JOIN 
		filtered_id AS f_id 
	ON 
		a.id = f_id.id 
	JOIN 
		real_estate.flats AS f 
	ON 
		a.id = f.id 
	JOIN 
		real_estate.city AS c 
	ON 
		f.city_id = c.city_id 
	JOIN 
		real_estate.type AS t 
	ON 
		f.type_id = t.type_id 
	WHERE 
		t.type = 'город') 
SELECT 
	region as регион, 
	activity_period as период_активности, 
	COUNT(id) AS кол_во_объявлений, 
	ROUND(COUNT(id) / SUM(COUNT(id)) OVER (PARTITION BY region)::numeric, 3) AS доля_в_периоде, 
	ROUND(AVG(price_sq_meter)::numeric, 2) AS ср_стоим_кв_м,
	ROUND(AVG(floors_total)::numeric, 2) AS ср_этажность,
	ROUND(AVG(rooms)::numeric, 2) AS ср_кол_во_комнат,
	ROUND(AVG(balcony)::numeric, 2) AS ср_кол_во_балконов,
	ROUND(AVG(total_area)::numeric, 2) AS ср_площадь,
	ROUND(AVG(ceiling_height)::numeric, 2) AS ср_высота_потолка, 
	ROUND((SELECT COUNT(*) FROM category WHERE rooms = 1 AND region = с.region AND activity_period = с.activity_period)::numeric/ COUNT(id), 2) AS доля_студий,
	ROUND((SELECT COUNT(*) FROM category WHERE rooms = 2 AND region = с.region AND activity_period = с.activity_period)::numeric/ COUNT(id), 2) AS доля_однокомнатн,
	ROUND((SELECT COUNT(*) FROM category WHERE rooms = 3 AND region = с.region AND activity_period = с.activity_period)::numeric/ COUNT(id), 2) AS доля_двухкомнатн
FROM 
	category as с 
GROUP BY 
	регион, период_активности 
ORDER BY 
	ср_стоим_кв_м DESC;


-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND rooms < (SELECT rooms_limit FROM limits)
        AND balcony < (SELECT balcony_limit FROM limits)
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
),
months AS (
    SELECT
        a.id,
        EXTRACT(MONTH FROM a.first_day_exposition) AS public_month,
        EXTRACT(MONTH FROM (a.first_day_exposition + a.days_exposition::integer)) AS remov_month
    FROM
        real_estate.advertisement AS a
    JOIN
        filtered_id AS f_id 
    ON 
    	a.id = f_id.id
    JOIN
        real_estate.flats AS f 
    ON 
    	a.id = f.id
    JOIN
        real_estate.type AS t 
    ON 
    	f.type_id = t.type_id
    WHERE 
        EXTRACT(YEAR FROM a.first_day_exposition) IN (2015, 2016, 2017, 2018)
        AND t.type = 'город'
),
remov_activity AS (
    SELECT
        remov_month,
        COUNT(id) AS remov_count,
        RANK() OVER (ORDER BY COUNT(id) DESC) AS remov_rank
    FROM
        months
    GROUP BY
        remov_month
),
public_activity AS (
    SELECT
        public_month,
        COUNT(id) AS public_count,
        RANK() OVER (ORDER BY COUNT(id) DESC) AS public_rank
    FROM
        months
    GROUP BY
        public_month
),
statistic AS (
    SELECT
        EXTRACT(MONTH FROM a.first_day_exposition) AS month,
        ROUND(AVG(a.last_price::numeric / f.total_area::numeric), 2) AS avg_price_sq_meter,
        ROUND(AVG(f.total_area)::numeric, 2) AS avg_total_area
    FROM
        real_estate.advertisement AS a
    JOIN
        real_estate.flats AS f 
    ON 
    	a.id = f.id
    JOIN
        filtered_id AS f_id 
    ON 
    	a.id = f_id.id
    JOIN
        real_estate.type AS t 
    ON 
    	f.type_id = t.type_id
    WHERE 
        EXTRACT(YEAR FROM a.first_day_exposition) IN (2015, 2016, 2017, 2018)
        AND t.type = 'город'
    GROUP BY
        EXTRACT(MONTH FROM a.first_day_exposition)
)
SELECT
    p.public_month AS месяц,
    p.public_count AS публикации,
    p.public_rank AS ранг_публикаций,
    r.remov_count AS снятия,
    r.remov_rank AS ранг_снятий,
    round(r.remov_count/p.public_count::numeric,2) AS доля_снятия, 
    s.avg_price_sq_meter AS ср_стоим_кв_м,
    s.avg_total_area AS ср_площадь
FROM
    public_activity AS p
JOIN
    remov_activity AS r 
ON 
    p.public_month = r.remov_month
JOIN
    statistic AS s 
ON 
    p.public_month = s.month
ORDER BY
    публикации DESC;


-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats),
filtered_id AS (
    SELECT
        a.id,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area,
        c.city,
        f.floors_total,
        f.rooms,
        ROUND(a.last_price::numeric / f.total_area::numeric, 2) AS price_sq_meter
    FROM
        real_estate.advertisement AS a
    JOIN
        real_estate.flats AS f ON a.id = f.id
    JOIN
        real_estate.city AS c ON f.city_id = c.city_id
    JOIN
        real_estate.type AS t ON f.type_id = t.type_id
    WHERE
        c.city != 'Санкт-Петербург'
        AND f.total_area < (SELECT total_area_limit FROM limits)
        AND f.rooms < (SELECT rooms_limit FROM limits)
        AND f.balcony < (SELECT balcony_limit FROM limits)
        AND f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
SELECT
    f.city as город,
    COUNT(f.id) AS кол_во_объявл_подано,
    COUNT(f.days_exposition) AS кол_во_объявл_снято,
    ROUND(COUNT(f.days_exposition)::numeric/ COUNT(f.id), 2) AS доля_объяв_снято,
    ROUND(AVG(f.price_sq_meter)::numeric, 2) AS ср_стоим_кв_м,
    ROUND(AVG(f.floors_total)::numeric, 2) AS ср_этажность,
	ROUND(AVG(f.rooms)::numeric, 2) AS ср_кол_во_комнат,
    ROUND(AVG(f.total_area)::numeric, 2) AS ср_площадь,
    ROUND(AVG(f.days_exposition)::numeric, 2) AS ср_длит_размещ
FROM
    filtered_id AS f
GROUP BY
    f.city
ORDER BY
    кол_во_объявл_подано DESC
LIMIT 15;
--    Порог фильтрации в топ-15 выбран для более широкого охвата данных по рынку недвижиомсти Ленинградской области.


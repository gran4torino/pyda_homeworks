SET search_path TO bookings


-------1.В каких городах больше одного аэропорта?--------

select
	city as "Города, где больше одного аэропорта"
/* в таблице аэропортов,с помощью оконной функции, пронумеруем города, с группировкой по каждому городу */
from
	(
	select
		airport_name,
		city,
		row_number() over(partition by city)
	from
		airports a  
	) as t
/* оставляем только те города, где порядковый номер кол-ва городов = 2 (т.е. больше 1 аэропорта) */
where
	row_number = 2


-------2.В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?--------

/* Оставляем в списке только уникальные коды аэропортов,
 * обогащаем данными из таблицы аэропортов, для добавления названия аэропорта */
select
	distinct (f.departure_airport) as "Код аэропорта",
	airport_name as "Название аэропорта"
from
	flights f 
/* Найдем код самолета с максимальной дальностью перелета:
 * Таблицу самолетов (aircrafts) сортируем по убыванию по столбцу расстояние (range), затем 
 * оставляем только первую строку,из нее берем поле с кодом самолета (aircraft_code).
 * По этому коду фильтруется вся таблица рейсов (flights) */
join airports a2 on
	f.departure_airport = a2.airport_code
where
	f.aircraft_code = (
	select
		a.aircraft_code
	from
		aircrafts a
	order by
		a."range" desc
	limit (1))


-------3. Вывести 10 рейсов с максимальным временем задержки вылета --------

	/*вычисляем время задержки полета как разницу между фактическим временем вылета и 
 * планируемым времененм вылета  */
select
	f.flight_no as "Номер рейса",
	f.actual_departure -f.scheduled_departure as "Время задержки вылета"
from
	flights f 
/*оставляем только те строки, где актуальное время вылета не равно null (фвктически только те 
 * рейсы, которые в состоянии departed или arrived)  */
where
	f.actual_departure is not null
order by
	("Время задержки вылета") desc 
/*оставляем первые 10 значений */
limit (10)

-------4.Были ли брони, по которым не были получены посадочные талоны?--------

/* 5. считаем количество строк в отчете, для получения количества броней без посадочных талонов */
select
	count(book_ref) over () as "Кол-во броней без пос.талонов"
from
	(
	select
		*
	from
		/*1. нумеруем по порядку строки в таблице, с группировкой по каждому номеру брони */
		(
		select
			b.book_ref,
			row_number () over(partition by b.book_ref)
		from
			bookings b 
		/* 2. обогащаем данными таблицу бронировок данными. Используем
		 * left join, чтобы в отчет попали все данные из левой таблицы.
		 * Это даст нам возможность увидель бронировки без посадочных талонов */
		left join tickets t on
			b.book_ref = t.book_ref
		left join ticket_flights tf on
			t.ticket_no = tf.ticket_no
		left join boarding_passes bp on
			tf.ticket_no = bp.ticket_no 
		/* 3.оставим в отчете только те строки, где нет посадочных талонов*/
		where
			boarding_no is null 
		) as t1
	/* 4.удаляем дубли броней, оставляя только строки с порядковым номером 1(нумерация была
	 * внутри каждой брони*/
	where
		row_number = 1
) as t_2
limit (1)/* 6. оставляем тоько первый результат, так как счетчик броней во всех строках одинаков*/



-----5.Найдите свободные места для каждого рейса, их % отношение к общему количеству-------
-----мест в самолете. Добавьте столбец с накопительным итогом - суммарное накопление------- 
-----количества вывезенных пассажиров из каждого аэропорта на каждый день. Т.е. в этом ----
-----столбце должна отражаться накопительная сумма - сколько человек уже вылетело из ------
-----данного аэропорта на этом или более ранних рейсах за день.----------------------------

/*создадим cte, который посчитает количество занятых мест на каждом рейсе  */
with cte_seats_per_flight_id as
(
select
	*
from
	(
	select
		flight_id,
		count(seat_no) over (partition by flight_id) as seats_in_flight,
		row_number () over (partition by flight_id)
	from
		boarding_passes bp 
	) as t1
where
	row_number = 1
),
/*создадим cte,  который посчитает вместительность самолета (в местах), по каждому самолету*/
cte_seats_in_aircrafts as
(
select
	aircraft_code,
	seats_in_aircraft
from
	(
	select
		aircraft_code,
		count(seat_no) over(partition by aircraft_code) as seats_in_aircraft,
		row_number() over(partition by aircraft_code)
	from
		seats
	)as t1
	/*убираем дубли из таблицы*/
where
	row_number = 1
	),
/* создадим cte, обогатим данными cte_seats_per_flight_id (количество занятых мест на каждом рейсе)
 * джоиним с 5 таблицами для получения данных по: дате вылета, коду аэропорта, модели самолета,
 * вместительности самолета. Создаем вычисляемый столбец с подсчетом свободных места не рейсе 
 * (вместительность самолета минус занятые места на рейсе. ) */
cte_aggregate_1 as 
(
select 
	scheduled_departure,
	actual_departure, 
	departure_airport ,
	airport_name,
	flight_no ,
	cte_seats_in_aircrafts.aircraft_code, 
	model,
	seats_in_flight,
	seats_in_aircraft, 
			seats_in_aircraft - seats_in_flight as free_seats_per_flight,
			/*С помощью оконнной функции row_number () over уберем дубли записей рейсов, с одинаковым времением вылета(
			 * дубли есть, так в таблице полетов на один вылет приходится множество записей (связана с по внешнему 
			 * ключу flight_id с таблицей билетов и посадочных талонов), группируем по номеру рейса и времени вылета */
			row_number () over (partition by flight_no,
	actual_departure)
from
	cte_seats_per_flight_id as cspfi
join ticket_flights tf on
	cspfi.flight_id = tf.flight_id
join flights f on
	tf.flight_id = f.flight_id
join aircrafts ac on
	f.aircraft_code = ac.aircraft_code
join cte_seats_in_aircrafts on
	ac.aircraft_code = cte_seats_in_aircrafts.aircraft_code
join airports a on
	f.departure_airport = a.airport_code 
)
/*создаем итоговую таблицу с необходимыми данными. Результаты берем из предыдущих запросов, так и из-подзапроса (расчет 
 * процента свободных мест на самолете)*/
select 
	scheduled_departure as "План. время вылета",
	actual_departure as "Факт. время вылета",
	airport_name as "Аэропорт", 
	flight_no as "N рейса", 
	model as "Самолет",
	seats_in_aircraft as "Вмест-сть сам-та, мест",
	seats_in_flight as "Мест на рейсе", 
	free_seats_per_flight as "Своб. мест на рейсе",
	free_seats_per_flight_percent as "% cвоб. мест",
	/*Только для тех строк, где время реального вылета не равно нулю:
	 * суммируем нарастающим итогом вылетевших пассажиров (группируем по аэропорту вылета, и дате вылета. Сортируем по 
	 * дате с временем вылета)*/
	case
		when actual_departure is not null
		then sum (seats_in_flight) over (partition by departure_airport,
		actual_departure::date
	order by
		actual_departure)
	end 
	as "Пассажиров,вылет.с нач.дня" 
	/*берем все данные из cte_aggregate_1, добавляем расчет процента свободных мест на самолете*/
from
	(
	select
		*,
		((free_seats_per_flight::float / seats_in_aircraft::float)* 100)::int as free_seats_per_flight_percent
	from
		cte_aggregate_1
	) as t2
/*убираем дубли вылетов (запрос в cte_aggregate_1),*/
where
	row_number = 1 


--------6.Найдите процентное соотношение перелетов по типам самолетов от общего количества----

select t.aircraft_code as "Код самолета", 
a.model as "Модель самолета",
/*2. вычисляем процент как количество полетов одного типа самолетов к общему количеству полетов;
 * общее количество полетов считаем как сумму всех полетов самолетов через оконную функцию
 * окруляем до второго знака после запятой*/
round (count(t.flight_no) / sum (count(t.flight_no)) over() * 100, 2)
as "% перелетов самолета от общ.кол-ва"
	from (
		/* 1. группируем коды самолетов по номеру рейса самолета*/
		select flight_no, aircraft_code 
		from flights f
		group by flight_no, f.aircraft_code
		) as t
/*3. джоиним с таблицей aicrafts, добавляем модель самолета в наш результат*/
join aircrafts a on t.aircraft_code = a.aircraft_code 
group by t.aircraft_code, a.model 
order by "% перелетов самолета от общ.кол-ва" desc


---------7. Были ли города, в которые можно  добраться бизнес - классом дешевле,--------
----------------- чем эконом-классом в рамках перелета?---------------------------------

/*создадим cte, с аэропортом назначения, стоимостью перелета и уровнем класса облуживания */
with cte_1 as 
	(
select
	arrival_airport,
	amount,
	fare_conditions
from
	flights f
join ticket_flights tf
		using (flight_id)
),
/* создадим cte_max_economy, где создадим столбец с максимальной ценой перелета эконом-класса, 
 * с группировкой по каждому аропорту*/
cte_max_economy as
(
select
	arrival_airport,
	max(amount) as max_economy
from
	cte_1
where
	fare_conditions = 'Economy'
group by
	arrival_airport,
	fare_conditions 
),
/* создадим cte_min_business, где создадим столбец с минимальной ценой перелета бизнесс-класса, 
 * с группировкой по каждому аропорту*/
cte_min_business as
(
select
	arrival_airport,
	min(amount) as min_business
from
	cte_1
where
	fare_conditions = 'Business'
group by
	arrival_airport,
	fare_conditions 
)
/* объединим cte_max_economy и cte_min_business по ключевому полю arrival_airport,
 * получив тем самым в строке с аэропортом назначения два значения:
 * с минимальной ценой перелета бизнесс-класса и максимальной ценой перелета эконом-класса*/
select
	distinct (city) as "Города"
from
	cte_min_business as cmb
join cte_max_economy
		using (arrival_airport)
/*объединим с таблицей аэропортов, чтобы достать названия  городов в наш отчет*/
join airports a on
	cmb.arrival_airport = a.airport_code 
/* оставим только те строки с, где минимальная цена перелета бизнесс-класса дешевле,
 * чем максимальная стоимость перелета эконом-класса  */
where
	min_business < max_economy
order by
	city


------8.Между какими городами нет прямых рейсов?----------

/* Делаем представление. Из таблицы перелетов убираем дубли аэропортов отлета и прибытия,
 * джоиним с таблицей городов*/
create view no_routes as 
with ct_routes as
(
select
	departure_city,
	city as arrival_city
from
	(
	select
		departure_airport,
		arrival_airport,
		city as departure_city
	from
		(
		select
			departure_airport,
			arrival_airport, 
				row_number() over(partition by departure_airport,
			arrival_airport)
		from
			flights f
			) as t1
	join airports a on
		t1.departure_airport = a.airport_code
	where
		row_number = 1
		) as t2
join airports a on
	t2.arrival_airport = a.airport_code 
),
/* создаем общий список всех городов, убираем дубли, создаем ct_all_departure_city*/
ct_all_departure_city as
	(
select
	distinct (departure_city)
from
	ct_routes
union
select
	distinct (arrival_city)
from
	ct_routes
	)
/*Для использования в декартовом произведении, создаем cte со списком городов прилета (ct_all_arrival_city).
 *  В таблице список городов тот же, что и в таблице гродов отлета (ct_all_departure_city)*/
,
ct_all_arrival_city as
	(
select
	departure_city as "arrival_city"
from
	ct_all_departure_city
order by
	arrival_city
	)	
/* используем декартово произведение с помощью двух таблиц с одним столбцом
 * (ы одной таблице города вылета, в другой - города прилета).Получаем все возможные комбинации городов.
 * Исключаем ищ отчета, что город отлета не должен быть равным городу прилета */
select
	*
from
	ct_all_departure_city,
	ct_all_arrival_city
where
	departure_city <> arrival_city
/*изо всех возможных комбинаций городов исключем реальные перелеты ct_routes.
 * Тем самым мы получим список городов, между которыми нет перелетов*/
except 
select
	*
from
	ct_routes
order by
	departure_city,
	arrival_city
	
------------9. Вычислите расстояние между аэропортами, связанными прямыми рейсами, ---------------------------
----сравните с допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы ---

/* Делаем представление. Из таблицы перелетов убираем дубли аэропортов отлета и прибытия,
 * джоиним с таблицей городов, аэропортами, самолетами. Получаем названия
 * аэропортв, координаты, модель самолета с макс. дальностью перелета*/
with ct_routes_with_dist as
(
select
	dep_airport_name,
	airport_name as arr_airport_name,
	depart_long,
	depart_lat,
	longitude as arrive_long,
	latitude as arrive_lat,
	aircraft_code,
	model,
	"range"
from
	(
	select
		departure_airport,
		arrival_airport,
		airport_name as dep_airport_name,
		longitude as depart_long,
		latitude as depart_lat,
		aircraft_code
	from
		(
		select
			departure_airport,
			arrival_airport,
			aircraft_code,
				/*нумерум пары аэропортов отлета и прибытия*/
				row_number() over(partition by departure_airport,
			arrival_airport)
		from
			flights f
			) as t1
	join airports a on
		t1.departure_airport = a.airport_code 
		/*убираем дубли пар аэропортов отлета и прибытия*/
	where
		row_number = 1
		) as t2
join airports a on
	t2.arrival_airport = a.airport_code
join aircrafts a2
		using(aircraft_code)
	),
	/*добавляям столбец с вычисленным расстоянием между аэропортами*/
ct_routes_with_dist_reserve 
	as (
select
	dep_airport_name ,
	arr_airport_name,
	round(
		(acos (sind(depart_lat)* sind(arrive_lat) + cosd(depart_lat)* cosd(arrive_lat)*
		cosd(depart_long - arrive_long)) * 6371)::int
		, 2) as dist_btwn_airports, 
		model,
	"range" as aircraft_range
from
	ct_routes_with_dist
)
/* лобавлянм столбец с расчетом запаса хода в перелете, сравнивая расстояния
 * между аэродромами с макс.дальностью полета самолета, сортируем по аэропортам
 * отлета и прибытия*/
select
	dep_airport_name as "Аэропорт вылета",
	arr_airport_name as "Аэропорт прилета", 
	dist_btwn_airports as "Расст. м/у аэропортами, км",
	model as "Модель самолета",
	aircraft_range as "Макс. дальность полета, км", 
	aircraft_range - dist_btwn_airports as "Запас хода в этом перелете , км",
	(case
		when aircraft_range - dist_btwn_airports >0 
	then 'Да'
		else 'Нет'
	end) as "Самолет долетит?"
from
	ct_routes_with_dist_reserve
order by
	dep_airport_name ,
	arr_airport_name


------------------------------Дополнительный расчет необходимых для бизнес-анализа метрик---------------
--------в  нем посчитаем недостающие нам метрики - 
--1. Вместимость (ASM);
--2. Трафик (RPM);
--3. коэффициент загрузки авиакомпании
--Коэффициент считается как отношение произведения количества заплативших пассажиров на пройденное-------
--расстояние к произведению количества доступных мест (вместимости самолета) на пройденное расстояние---- 

-------------
/*создадим cte, который посчитает количество занятых мест на каждом рейсе  */
with cte_seats_per_flight_id as
(
select
	*
from
	(
	select
		flight_id,
		count(seat_no) over (partition by flight_id) as seats_in_flight,
		row_number () over (partition by flight_id)
	from
		boarding_passes bp 
	) as t1
where
	row_number = 1
),
/*создадим cte,  который посчитает вместительность самолета (в местах), по каждому самолету*/
cte_seats_in_aircrafts as
(
select
	aircraft_code,
	seats_in_aircraft
from
	(
	select
		aircraft_code,
		count(seat_no) over(partition by aircraft_code) as seats_in_aircraft,
		row_number() over(partition by aircraft_code)
	from
		seats
	)as t1
	/*убираем дубли из таблицы*/
where
	row_number = 1
	),
/* создадим cte, обогатим данными cte_seats_per_flight_id (количество занятых мест на каждом рейсе)
 * джоиним с 5 таблицами для получения данных по: дате вылета, коду аэропорта, модели самолета,
 * вместительности самолета.*/
cte_aggregate_1 as 
(
select 
	scheduled_departure,
	actual_departure, 
	departure_airport ,
	a.longitude as depart_long,
	a.latitude as depart_lat,
	a2.longitude as arrive_long,
	a2.latitude as arrive_lat,
	arrival_airport,
	a.airport_name,
	flight_no ,
	cte_seats_in_aircrafts.aircraft_code, 
	model,
	seats_in_flight,
	seats_in_aircraft, 
			seats_in_aircraft - seats_in_flight as free_seats_per_flight,
			/*С помощью оконнной функции row_number () over уберем дубли записей рейсов, с одинаковым времением вылета(
			 * дубли есть, так в таблице полетов на один вылет приходится множество записей (связана с по внешнему 
			 * ключу flight_id с таблицей билетов и посадочных талонов), группируем по номеру рейса и времени вылета */
			row_number () over (partition by flight_no,
	actual_departure)
from
	cte_seats_per_flight_id as cspfi
join ticket_flights tf on
	cspfi.flight_id = tf.flight_id
join flights f on
	tf.flight_id = f.flight_id
join aircrafts ac on
	f.aircraft_code = ac.aircraft_code
join cte_seats_in_aircrafts on
	ac.aircraft_code = cte_seats_in_aircrafts.aircraft_code
join airports a on
	f.departure_airport = a.airport_code
join airports a2 on	
	f.arrival_airport = a2.airport_code
)
select
	(asm * 0.62137)::int as "Вместимость (ASM)" ,
	(rpm  * 0.62137)::int as "Трафик (RPM)",
	round (rpm / asm , 2) as "Коэффициент загрузки авиакомпании (RPM/ASM)"
from
	(/*создаем итоговую таблицу с необходимыми данными. Результаты берем из предыдущих запросов*/
	select
		sum(
	seats_in_flight * round(
		(acos (sind(depart_lat)* sind(arrive_lat) + cosd(depart_lat)* cosd(arrive_lat)*
		cosd(depart_long - arrive_long)) * 6371)::int, 2)) over() as RPM,
		sum(
		seats_in_aircraft * round(
		(acos (sind(depart_lat)* sind(arrive_lat) + cosd(depart_lat)* cosd(arrive_lat)*
		cosd(depart_long - arrive_long)) * 6371)::int, 2)) over() as ASM
	from
		(
		select
			*,
			((free_seats_per_flight::float / seats_in_aircraft::float)* 100)::int as free_seats_per_flight_percent
		from
			cte_aggregate_1
	) as t2
/*убираем дубли вылетов (запрос в cte_aggregate_1),*/
	where
		row_number = 1
	limit (1)	
)as t_main